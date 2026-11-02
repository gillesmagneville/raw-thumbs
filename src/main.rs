//! RAW thumbnailer for Nautilus / GNOME (freedesktop.org thumbnailer spec).
//!
//! Called by Nautilus as: raw-thumbs %i %o %s
//!   %i = path (or file:// URI) of the input RAW file
//!   %o = path of the expected output PNG
//!   %s = requested size (the longest side, in pixels)
//!
//! Two-level strategy:
//!   1. Extraction of the embedded JPEG thumbnail (fast, covers the vast
//!      majority of real-world RAW files).
//!   2. Fallback to a full RAW decode (demosaicing) if the file has no
//!      usable embedded thumbnail.
//!
//! In both cases libraw (a dynamically linked C library) does the decoding
//! work — this program only orchestrates the calls and handles the
//! resizing and the PNG writing.

use std::env;
use std::ffi::CString;
use std::process::ExitCode;
use std::slice;

use image::{DynamicImage, ImageBuffer, Rgb};
use libraw_sys as raw;

/// Internal result: either an already encoded JPEG, or a raw RGB bitmap.
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
        eprintln!("Usage: {} <raw_input> <output.png> <size>", args[0]);
        return ExitCode::FAILURE;
    }

    // Depending on the version, Nautilus sometimes passes a file:// URI and
    // sometimes a plain local path — we handle both.
    let input_path = args[1].strip_prefix("file://").unwrap_or(&args[1]);
    let output_path = &args[2];
    let target_size: u32 = match args[3].parse() {
        Ok(s) => s,
        Err(_) => {
            eprintln!("Invalid size: {}", args[3]);
            return ExitCode::FAILURE;
        }
    };

    match run(input_path, output_path, target_size) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            // A freedesktop thumbnailer must fail silently as far as the
            // user is concerned: Nautilus falls back to the generic icon.
            // The message is kept on stderr for debugging.
            eprintln!("raw-thumbs: {input_path}: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run(input_path: &str, output_path: &str, target_size: u32) -> Result<(), String> {
    let handle = unsafe { raw::libraw_init(0) };
    if handle.is_null() {
        return Err("libraw_init failed".into());
    }

    // Minimal RAII: guarantees the libraw handle is released whatever the
    // exit path (success or error).
    struct LibRawGuard(*mut raw::libraw_data_t);
    impl Drop for LibRawGuard {
        fn drop(&mut self) {
            unsafe { raw::libraw_close(self.0) };
        }
    }
    let _guard = LibRawGuard(handle);

    let c_path = CString::new(input_path).map_err(|_| "invalid path (NUL byte)".to_string())?;
    let open_result = unsafe { raw::libraw_open_file(handle, c_path.as_ptr()) };
    if open_result != raw::LIBRAW_SUCCESS as i32 {
        return Err(format!("libraw_open_file failed (code {open_result})"));
    }

    // Expected orientation (0 = none, 3 = 180°, 5 = 90° counter-clockwise,
    // 6 = 90° clockwise — see the LibRaw documentation on
    // libraw_image_sizes_t.flip), already known at this stage since
    // open_file() reads all the orientation tags while identifying the file.
    let flip = unsafe { (*handle).sizes.flip };

    // --- Level 1: embedded thumbnail ---
    if let Some(img) = try_extract_embedded_thumb(handle) {
        if let Ok(dynimg) = decode_extracted(img) {
            // The embedded thumbnail (a JPEG in particular) is the blob as
            // stored by the camera: unlike dcraw_make_mem_image (used at
            // level 2), it is NOT reoriented by libraw internally. We
            // therefore apply the rotation ourselves here.
            let oriented = apply_orientation(dynimg, flip);
            return save_resized(oriented, target_size, output_path);
        }
        // The embedded thumbnail exists but could not be decoded (exotic or
        // corrupt format): we try the full path rather than give up.
    }

    // --- Level 2: full RAW decode (fallback) ---
    // No call to apply_orientation here: dcraw_make_mem_image already
    // applies the rotation itself in its output phase (libraw's default
    // behaviour, user_flip being -1 as long as we do not change it).
    // Applying it a second time would rotate the image twice.
    let img = full_decode(handle)?;
    let dynimg = decode_extracted(img).map_err(|e| format!("full decode: {e}"))?;
    save_resized(dynimg, target_size, output_path)
}

/// Applies the rotation given by `libraw_image_sizes_t.flip` to a thumbnail
/// extracted as is (the "embedded thumbnail" path only — see the comment in
/// `run()` for why the full decode path does not need it).
fn apply_orientation(img: DynamicImage, flip: i32) -> DynamicImage {
    match flip {
        3 => img.rotate180(),
        5 => img.rotate270(), // 90° counter-clockwise
        6 => img.rotate90(),  // 90° clockwise
        _ => img,
    }
}

/// Tries to extract the JPEG/bitmap thumbnail embedded in the RAW file.
/// Returns None if no usable thumbnail is present.
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

/// Full RAW decode (demosaicing) — the slow path, used only as a fallback
/// when no embedded thumbnail is available.
fn full_decode(handle: *mut raw::libraw_data_t) -> Result<ExtractedImage, String> {
    let r = unsafe { raw::libraw_unpack(handle) };
    if r != raw::LIBRAW_SUCCESS as i32 {
        return Err(format!("libraw_unpack failed (code {r})"));
    }
    let r = unsafe { raw::libraw_dcraw_process(handle) };
    if r != raw::LIBRAW_SUCCESS as i32 {
        return Err(format!("libraw_dcraw_process failed (code {r})"));
    }

    let mut errc: i32 = 0;
    let img_ptr = unsafe { raw::libraw_dcraw_make_mem_image(handle, &mut errc) };
    if img_ptr.is_null() || errc != 0 {
        return Err(format!("libraw_dcraw_make_mem_image failed (code {errc})"));
    }

    let result = extract_processed_image(img_ptr).ok_or_else(|| "unexpected image format".to_string());
    unsafe { raw::libraw_dcraw_clear_mem(img_ptr) };
    result
}

/// Copies the useful data of a `libraw_processed_image_t*` before libraw
/// frees the underlying memory.
fn extract_processed_image(ptr: *mut raw::libraw_processed_image_t) -> Option<ExtractedImage> {
    let img = unsafe { &*ptr };
    let data_ptr = img.data.as_ptr();
    let data_len = img.data_size as usize;
    let data_slice = unsafe { slice::from_raw_parts(data_ptr, data_len) };

    // The crate's LibRaw_image_formats enum does not derive PartialEq: we
    // therefore compare on the raw discriminant (1 = JPEG, 2 = BITMAP, see
    // libraw_const.h) rather than by pattern matching.
    // The raw discriminant is read through a pointer (the #[repr(C)] enum
    // has the same layout as a c_int) since the type does not derive Copy.
    let image_type_raw = unsafe { *(&img.image_type as *const raw::LibRaw_image_formats as *const i32) };
    match image_type_raw {
        1 => Some(ExtractedImage::Jpeg(data_slice.to_vec())),
        2 => {
            // Raw RGB bitmap. Only the standard case is handled: 8 bits per
            // channel, 3 colors (RGB) — the overwhelming majority of the
            // output of dcraw_process with the default settings.
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
                .map_err(|e| format!("embedded JPEG decode: {e}"))
        }
        ExtractedImage::Bitmap { width, height, data } => {
            let buf: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::from_raw(width, height, data)
                .ok_or_else(|| "inconsistent bitmap dimensions".to_string())?;
            Ok(DynamicImage::ImageRgb8(buf))
        }
    }
}

fn save_resized(img: DynamicImage, target_size: u32, output_path: &str) -> Result<(), String> {
    let resized = img.resize(target_size, target_size, image::imageops::FilterType::Lanczos3);
    resized
        .save_with_format(output_path, image::ImageFormat::Png)
        .map_err(|e| format!("PNG write: {e}"))
}
