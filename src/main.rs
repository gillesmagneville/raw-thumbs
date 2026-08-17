//! Thumbnailer RAW pour Nautilus / GNOME (spec freedesktop.org thumbnailer).
//!
//! Appelé par Nautilus comme : raw-thumbs %i %o %s
//!   %i = chemin (ou URI file://) du fichier RAW en entrée
//!   %o = chemin du PNG de sortie attendu
//!   %s = taille demandée (le plus grand côté, en pixels)
//!
//! Stratégie à deux niveaux :
//!   1. Extraction de la vignette JPEG embarquée (rapide, couvre la grande
//!      majorité des fichiers RAW réels).
//!   2. Repli sur un décodage RAW complet (dématriçage) si le fichier n'a
//!      pas de vignette embarquée exploitable.
//!
//! Dans les deux cas, c'est libraw (bibliothèque C liée dynamiquement) qui
//! fait le travail de décodage — ce programme ne fait qu'orchestrer les
//! appels et gérer le redimensionnement/l'écriture PNG.

use std::env;
use std::ffi::CString;
use std::process::ExitCode;
use std::slice;

use image::{DynamicImage, ImageBuffer, Rgb};
use libraw_sys as raw;

/// Résultat interne : soit du JPEG déjà encodé, soit un bitmap RGB brut.
enum ExtractedImage {
    Jpeg(Vec<u8>),
    Bitmap {
        width: u32,
        height: u32,
        data: Vec<u8>,
    },
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: {} <entree_raw> <sortie.png> <taille>", args[0]);
        return ExitCode::FAILURE;
    }

    // Nautilus passe parfois une URI file://, parfois un chemin local direct
    // selon la version — on gère les deux.
    let input_path = args[1].strip_prefix("file://").unwrap_or(&args[1]);
    let output_path = &args[2];
    let target_size: u32 = match args[3].parse() {
        Ok(s) => s,
        Err(_) => {
            eprintln!("Taille invalide: {}", args[3]);
            return ExitCode::FAILURE;
        }
    };

    match run(input_path, output_path, target_size) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            // Un thumbnailer freedesktop doit échouer silencieusement du
            // point de vue de l'utilisateur : Nautilus retombe sur l'icône
            // générique. On garde le message sur stderr pour le débogage.
            eprintln!("raw-thumbs: {input_path}: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run(input_path: &str, output_path: &str, target_size: u32) -> Result<(), String> {
    let handle = unsafe { raw::libraw_init(0) };
    if handle.is_null() {
        return Err("échec de libraw_init".into());
    }

    // RAII minimal : on garantit la libération du handle libraw quel que
    // soit le chemin de sortie (succès ou erreur).
    struct LibRawGuard(*mut raw::libraw_data_t);
    impl Drop for LibRawGuard {
        fn drop(&mut self) {
            unsafe { raw::libraw_close(self.0) };
        }
    }
    let _guard = LibRawGuard(handle);

    let c_path = CString::new(input_path).map_err(|_| "chemin invalide (NUL byte)".to_string())?;
    let open_result = unsafe { raw::libraw_open_file(handle, c_path.as_ptr()) };
    if open_result != raw::LIBRAW_SUCCESS as i32 {
        return Err(format!("libraw_open_file a échoué (code {open_result})"));
    }

    // --- Niveau 1 : vignette embarquée ---
    if let Some(img) = try_extract_embedded_thumb(handle) {
        if let Ok(dynimg) = decode_extracted(img) {
            return save_resized(dynimg, target_size, output_path);
        }
        // La vignette embarquée existe mais n'a pas pu être décodée
        // (format exotique/corrompu) : on retente le chemin complet plutôt
        // que d'abandonner.
    }

    // --- Niveau 2 : décodage RAW complet (repli) ---
    let img = full_decode(handle)?;
    let dynimg = decode_extracted(img).map_err(|e| format!("décodage complet: {e}"))?;
    save_resized(dynimg, target_size, output_path)
}

/// Tente d'extraire la vignette JPEG/bitmap embarquée dans le fichier RAW.
/// Retourne None si aucune vignette exploitable n'est présente.
fn try_extract_embedded_thumb(handle: *mut raw::libraw_data_t) -> Option<ExtractedImage> {
    let unpack_result = unsafe { raw::libraw_unpack_thumb(handle) };
    if unpack_result != raw::LIBRAW_SUCCESS as i32 {
        return None;
    }

    let mut errc: i32 = 0;
    let thumb_ptr = unsafe { raw::libraw_dcraw_make_mem_thumb(handle, &mut errc) };
    if thumb_ptr.is_null() || errc != 0 {
        return None;
    }

    let result = extract_processed_image(thumb_ptr);
    unsafe { raw::libraw_dcraw_clear_mem(thumb_ptr) };
    result
}

/// Décodage RAW complet (dématriçage) — chemin lent, utilisé uniquement en
/// repli quand aucune vignette embarquée n'est disponible.
fn full_decode(handle: *mut raw::libraw_data_t) -> Result<ExtractedImage, String> {
    let r = unsafe { raw::libraw_unpack(handle) };
    if r != raw::LIBRAW_SUCCESS as i32 {
        return Err(format!("libraw_unpack a échoué (code {r})"));
    }
    let r = unsafe { raw::libraw_dcraw_process(handle) };
    if r != raw::LIBRAW_SUCCESS as i32 {
        return Err(format!("libraw_dcraw_process a échoué (code {r})"));
    }

    let mut errc: i32 = 0;
    let img_ptr = unsafe { raw::libraw_dcraw_make_mem_image(handle, &mut errc) };
    if img_ptr.is_null() || errc != 0 {
        return Err(format!("libraw_dcraw_make_mem_image a échoué (code {errc})"));
    }

    let result = extract_processed_image(img_ptr).ok_or_else(|| "format image inattendu".to_string());
    unsafe { raw::libraw_dcraw_clear_mem(img_ptr) };
    result
}

/// Copie les données utiles d'un `libraw_processed_image_t*` avant que
/// libraw ne libère la mémoire sous-jacente.
fn extract_processed_image(ptr: *mut raw::libraw_processed_image_t) -> Option<ExtractedImage> {
    let img = unsafe { &*ptr };
    let data_ptr = img.data.as_ptr();
    let data_len = img.data_size as usize;
    let data_slice = unsafe { slice::from_raw_parts(data_ptr, data_len) };

    // L'énum LibRaw_image_formats du crate ne dérive pas PartialEq : on
    // compare donc sur le discriminant brut (1 = JPEG, 2 = BITMAP, cf.
    // libraw_const.h) plutôt que par filtrage de motif.
    // Lecture du discriminant brut via un pointeur (l'énum #[repr(C)] a le
    // même layout qu'un c_int) puisque le type ne dérive pas Copy.
    let image_type_raw = unsafe { *(&img.image_type as *const raw::LibRaw_image_formats as *const i32) };
    match image_type_raw {
        1 => Some(ExtractedImage::Jpeg(data_slice.to_vec())),
        2 => {
            // Bitmap RGB brut. On ne gère que le cas standard 8 bits/canal,
            // 3 couleurs (RGB) — c'est le cas de très large majorité en
            // sortie de dcraw_process avec les réglages par défaut.
            if img.colors != 3 || img.bits != 8 {
                return None;
            }
            Some(ExtractedImage::Bitmap {
                width: img.width as u32,
                height: img.height as u32,
                data: data_slice.to_vec(),
            })
        }
        _ => None,
    }
}

fn decode_extracted(img: ExtractedImage) -> Result<DynamicImage, String> {
    match img {
        ExtractedImage::Jpeg(bytes) => {
            image::load_from_memory_with_format(&bytes, image::ImageFormat::Jpeg)
                .map_err(|e| format!("décodage JPEG embarqué: {e}"))
        }
        ExtractedImage::Bitmap { width, height, data } => {
            let buf: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| "dimensions bitmap incohérentes".to_string())?;
            Ok(DynamicImage::ImageRgb8(buf))
        }
    }
}

fn save_resized(img: DynamicImage, target_size: u32, output_path: &str) -> Result<(), String> {
    let resized = img.resize(target_size, target_size, image::imageops::FilterType::Lanczos3);
    resized
        .save_with_format(output_path, image::ImageFormat::Png)
        .map_err(|e| format!("écriture PNG: {e}"))
}
