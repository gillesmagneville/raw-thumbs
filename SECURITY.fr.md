# Politique de sécurité

🇬🇧 [English version](SECURITY.md)

raw-thumbs est maintenu par une seule personne, à titre bénévole. Cette page explique comment signaler un problème de sécurité et ce que vous pouvez en attendre.

## Versions prises en charge

Seule la **dernière version publiée** reçoit les correctifs de sécurité. Si vous utilisez une version plus ancienne, mettez-la d'abord à jour : le paquet est sur la page des [Releases](https://github.com/gillesmagneville/raw-thumbs/releases) et les changements sont listés dans le [CHANGELOG](CHANGELOG.fr.md).

## Signaler une vulnérabilité

**Merci de ne pas signaler une vulnérabilité dans une issue, une pull request ou une discussion publique** : n'importe qui pourrait la lire avant qu'un correctif existe.

Signalez-la en privé, de l'une de ces deux façons :

1. **Sur GitHub** : ouvrez l'[onglet Security](https://github.com/gillesmagneville/raw-thumbs/security) du dépôt et cliquez sur **Report a vulnerability**. Seuls vous et le mainteneur voyez le signalement.
2. **Par courriel** : écrivez à [gilles@magneville.fr](mailto:gilles@magneville.fr) avec l'objet « raw-thumbs sécurité ».

Indiquez, autant que possible :

- la version du paquet (`dpkg -s raw-thumbs`), la version de libraw (`dpkg -l 'libraw*'`) et votre distribution ;
- la description du problème et les étapes pour le reproduire ;
- l'impact que vous lui voyez ;
- si le problème vient d'un fichier particulier, ce fichier — seulement si vous avez le droit de le partager.

## Ce que vous pouvez attendre

Ce sont des objectifs, pas des garanties, puisqu'il n'y a qu'un seul mainteneur :

- un accusé de réception de votre signalement sous **7 jours** ;
- une réponse indiquant s'il est considéré comme une vulnérabilité, puis des nouvelles au moins toutes les quelques semaines jusqu'à ce que le sujet soit réglé ;
- un correctif publié dans une **nouvelle version**, mentionné dans le CHANGELOG ; pour un problème grave, un avis de sécurité GitHub également ;
- vous êtes cité dans les notes de version, sauf si vous préférez rester anonyme.

Merci de garder les détails confidentiels jusqu'à la publication d'une version corrigée, pour que les utilisateurs aient le temps de mettre à jour.

## Ce qui est concerné

raw-thumbs n'a pas de fenêtre, travaille sur votre ordinateur et n'utilise pas le réseau. Ce qui le rend sensible, c'est que **Nautilus le lance tout seul sur chaque fichier RAW affiché dans un dossier**, sans que vous ouvriez le fichier : un fichier reçu par courriel ou téléchargé suffit. Nautilus exécute les générateurs de vignettes dans un bac à sable, ce qui limite les conséquences d'une faille sans rendre un signalement moins utile. Un signalement est pertinent, par exemple, si :

- un fichier RAW (ou tout fichier auquel on a donné un type RAW) fait planter raw-thumbs d'une façon exploitable, lui fait exécuter du code, ou lui fait lire ou écrire autre chose que la vignette qu'il doit produire ;
- le paquet `.deb`, son script d'installation, le fichier `.thumbnailer` ou les scripts de publication peuvent être détournés ;
- un fichier d'une version publiée ne correspond pas à son empreinte `.sha256` publiée.

## Ce qui n'est pas concerné

- Une vulnérabilité dans **libraw** elle-même : cette bibliothèque en C ne fait pas partie de raw-thumbs, elle vient de votre distribution (paquet `libraw23t64`). Merci de la signaler au projet LibRaw et à votre distribution ; mettre ce paquet à jour suffit. Dites-moi en revanche si raw-thumbs doit aussi être modifié.
- Une vulnérabilité dans la **bibliothèque Rust `image`**, intégrée au programme : merci de la signaler à ce projet, et prévenez-moi aussi, puisque le correctif demande une nouvelle version de raw-thumbs.
- Une vulnérabilité dans **Nautilus, GNOME ou la manière dont les générateurs de vignettes sont lancés** (y compris leur bac à sable) : merci de la signaler au projet ou à la distribution concernés.
- Les problèmes qui supposent un ordinateur déjà compromis, ou un accès physique à celui-ci.
- Les bugs ordinaires sans conséquence pour la sécurité (une vignette qui n'apparaît pas, par exemple) : ouvrez plutôt une [issue](https://github.com/gillesmagneville/raw-thumbs/issues).

## Vérifier ce que vous téléchargez

Téléchargez le paquet uniquement depuis la page des [Releases](https://github.com/gillesmagneville/raw-thumbs/releases) de ce dépôt. Il est publié avec son fichier `.sha256`. Pour vérifier un téléchargement, placez le paquet et son fichier `.sha256` dans le même dossier :

```bash
sha256sum -c raw-thumbs_X.Y.Z_amd64.deb.sha256
```
