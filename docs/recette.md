# Recette manuelle — sur poste réel

L'interface WPF et les effets sur le système ne se testent qu'à la main. Cette liste est déroulée
à la fin de chaque itération sur un poste de test, puis complétée par l'itération suivante.
Cocher, dater, noter le modèle de poste et joindre le journal (`logs\Journal_*.log`).

## Itération 0 — parité avec le prototype (simulation)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

### Démarrage
- [ ] `Lancer.cmd` demande l'élévation, puis la fenêtre s'ouvre (taille et charte identiques à la maquette validée).
- [ ] Lancé sans droits administrateur (`Preparation.ps1` directement) : message « Cet outil doit être lancé en administrateur ».
- [ ] `config.json` invalide (ex. retirer `Power.ApplyOnBattery`) : message qui cite la clé, l'outil ne s'ouvre pas.
- [ ] `Lancer.cmd -Real` : message « mode réel pas encore disponible ».
- [ ] Bandeau « MODE SIMULATION » visible.
- [ ] Clé en lecture seule : journal écrit dans `%TEMP%\FastPrepare`, ligne `[ATTN]` qui le signale.

### Section 0 — connexion
- [ ] Pastille rouge puis verte en quelques secondes ; une seule ligne « Connexion internet validée ».
- [ ] Câble/Wi-Fi coupé : pastille rouge, Lancer grisé « connexion internet non validée » ; rétabli : vert.

### Sections 1 à 10
- [ ] 1 : champ grisé si décoché ; `123`, `PC_1`, 16 caractères → motif en rouge sous le champ, Lancer grisé ; `PC-01` → Lancer actif.
- [ ] 2 : même liste que le Panneau de configuration ; colonne « Silencieux » ; « Tout cocher » coche/décoche tout.
- [ ] 3 : « Dossier OneDrive » grisé quand OneDrive est décoché ; nombre de fichiers affiché.
- [ ] 4 : comptes supprimables listés ; exclus d'office : Administrateur, Invité, DefaultAccount, WDAGUtilityAccount, compte connecté.
- [ ] 5 : quatre cards (logos si présents dans `logos\`) ; la marque du poste est présélectionnée ; une seule card à la fois ; re-clic = désélection ; ligne `[SIMU] Utilitaire sélectionné` au clic.
- [ ] 6 : quatre cards ; pastilles Avec / Sans Teams seulement pour 365 ; « Inclure » grisé sans édition ; texte d'information (ID produit, exclusions) à jour.
- [ ] 7 : « MàJ utilitaire » grisée sans card en section 5, cochée d'elle-même quand une card est choisie.
- [ ] 8 : Adobe Acrobat Reader coché par défaut.
- [ ] 9 : une case par carte physique, décochée si IPv6 est déjà désactivé ; libellé alimentation conforme à `config.json`.
- [ ] 10 : N/S et MAC affichés ; « Copier » remplit le presse-papiers ; fichier `Inventaire_<N/S>_<horodatage>.txt` présent.

### Lancer (simulation)
- [ ] Les actions cochées apparaissent dans l'ordre du cahier (1 → 14), silencieuses avant assistants.
- [ ] XML ODT affiché pour l'édition choisie ; ID `O365BusinessEEANoTeamsRetail` si « Sans Teams ».
- [ ] Rappel final des actions manuelles = liste du mémo.
- [ ] Aucune modification du poste (nom, logiciels, comptes, IPv6, alimentation inchangés).

## Itération 1 — détections en arrière-plan

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] La fenêtre s'affiche immédiatement ; « Détection du poste… » dans l'en-tête, « Détection en cours… » dans les sections 2, 4, 9 et 10.
- [ ] Pendant la détection, la fenêtre reste réactive : on peut cocher, faire défiler, saisir dans un champ ; la pastille de connexion passe au vert.
- [ ] Lancer reste grisé « détection du poste en cours » jusqu'à la fin du relevé.
- [ ] Une card constructeur cliquée pendant la détection reste sélectionnée après le relevé (pas d'écrasement par la présélection).
- [ ] À la fin du relevé, toutes les sections sont remplies comme à l'itération 0 ; aucune ligne `[ERREUR]` dans le journal.
- [ ] Fermer la fenêtre pendant la détection : l'outil se ferme sans message d'erreur.

## Itération 2 — plan d'exécution unique (simulation)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Lancer : chaque action cochée apparaît avec le préfixe `[ETAPE nn/13 · section s]`, dans l'ordre du cahier (2 → 13), quel que soit l'ordre de saisie.
- [ ] Office Click-to-Run + MSI cochés : une seule ligne ODT de suppression, suivie du XML (`Remove All`, `RemoveMSI`).
- [ ] « Outlook classique » seul (Office décoché) : avertissement `[ATTN]`, aucune action.
- [ ] Désinstallations : silencieuses d'abord, assistants en dernier, en `[ATTN]`.
- [ ] Carte réseau dont IPv6 est déjà désactivé cochée : aucune action pour elle.
- [ ] Pendant l'exécution : colonnes grisées, « Exécution en cours… » ; à la fin, formulaire de nouveau utilisable.
- [ ] Rapport final : nombre d'actions, emplacement de l'inventaire et du journal, rappels manuels.

## Itération 3 — premier mode réel (poste de test uniquement)

> À dérouler sur un **poste de test réinitialisé**, jamais sur un poste en service.

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] `Lancer.cmd -Real` : bandeau rouge « MODE RÉEL — le poste sera modifié ».
- [ ] Lancer : boîte de confirmation avec le nombre d'actions et le nombre d'actions ignorées (étapes pas encore disponibles en réel) ; « Non » n'exécute rien.
- [ ] Alimentation : après exécution, `powercfg /query` montre 5 min (écran) et 15 min (veille), sur secteur et sur batterie.
- [ ] IPv6 : désactivé sur les cartes cochées (`Get-NetAdapterBinding -ComponentID ms_tcpip6`), inchangé sur les autres.
- [ ] Adobe Acrobat Reader installé (64 bits) ; relancer : ligne « déjà installé », pas d'erreur.
- [ ] winget absent (désinstaller le « Programme d'installation d'application » sur un poste de test) : réenregistrement, sinon installation depuis `packages\`.
- [ ] Actions des étapes non disponibles : lignes `[ATTN] … ignorée`, rien de modifié (Office, Teams, OneDrive toujours présents).
- [ ] Une action en échec (ex. carte réseau débranchée puis renommée) : ligne rouge, les actions suivantes s'exécutent.
- [ ] Noter les codes de sortie de winget observés (journal, lignes `[DEBUG]`).

## Itération 4 — désinstallations réelles (poste de test uniquement)

> **Actions destructives.** Poste de test réinitialisé, sans aucune donnée à conserver.
> Préparer : Office Click-to-Run, Office MSI 2016, Teams classique (Machine-Wide Installer) et nouveau Teams,
> nouvel Outlook, OneDrive avec des fichiers synchronisés, deux comptes locaux supplémentaires
> (dont un avec une session ouverte), un logiciel MSI, un logiciel Inno Setup, un logiciel NSIS, un logiciel à assistant.

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Sessions locales : compte et dossier de profil supprimés ; le compte à session ouverte est refusé (« profil chargé »), les autres actions continuent.
- [ ] Office : un seul passage ODT ; Click-to-Run et MSI désinstallés ; XML présent dans `C:\ODT` et dans le journal.
- [ ] Nouvel Outlook, OneNote (Store), nouveau Teams, Teams personnel : absents pour tous les utilisateurs **et** pour un nouveau profil créé ensuite (paquets provisionnés retirés).
- [ ] Teams classique : Machine-Wide Installer désinstallé, dossier `%LocalAppData%\Microsoft\Teams` du compte connecté supprimé.
- [ ] OneDrive : désinstallé ; un nouveau profil ne le réinstalle pas (clé `Run` du profil Default retirée).
- [ ] Dossier OneDrive : supprimé seulement si sa case est cochée ; jamais le profil entier.
- [ ] Logiciels : silencieux d'abord (MSI, Inno, NSIS : plus listés à la fin), assistant ensuite (l'outil attend sa fermeture) ; assistant **annulé** : action en échec « toujours présent ».
- [ ] Relancer l'outil sur le même poste : tout est « déjà absent », aucune erreur.

## Itération 5 — utilitaire constructeur (poste de test de chaque marque)

> Renseigner d'abord le lien de Thin Installer dans `config.json` (`Utilities.lenovo.Install[1].Url`, et si possible `Sha256`).

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Mode réel : la card de la marque est présélectionnée ; sous les cards, « préchargement en cours… » puis « préchargé » (Dell, Lenovo) ou « installation par winget à l'exécution » (HP, Fujitsu).
- [ ] Simulation : aucun dossier `%ProgramData%\FastPrepare` créé.
- [ ] Dell, DCU 5.7.0 : runtime .NET Desktop 8.0.25 installé avant DCU (si aucun 8.0.8–8.0.25 présent) ; DCU démarre.
- [ ] Dell, DCU 5.7.1 (quand winget la propose) : runtime .NET 10 (≥ 10.0.8).
- [ ] Dell avec un .NET 8 plus récent que 8.0.25 déjà présent : avertissement dans le journal.
- [ ] Lenovo : Commercial Vantage installé depuis le Store ; Thin Installer installé silencieusement depuis le fichier préchargé (ligne « Fichier préchargé utilisé ») ; signature Lenovo acceptée.
- [ ] HP, Fujitsu : outil installé par winget.
- [ ] MàJ utilitaire (section 7) : outil trouvé, mise à jour lancée sans redémarrage automatique ; **noter le code de sortie** (journal, `[DEBUG]`) avec et sans mise à jour disponible, pour confirmer `SuccessExitCodes` / `RebootExitCodes` (QO4).
- [ ] Noter le chemin réel de `HPImageAssistant.exe` et `ducmd.exe` après installation par winget.

## Itération 6 — installation d'Office (poste de test)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] 365 Apps for Business « Avec Teams » : installé (`O365BusinessRetail`), Teams présent, langue du système, 64 bits.
- [ ] 365 « Sans Teams (EEE) » : `O365BusinessEEANoTeamsRetail`, Teams absent.
- [ ] LTSC Pro Plus 2024, Standard 2019, Pro Plus 2019 : installés (`ProPlus2024Volume`, `Standard2019Volume`, `ProPlus2019Volume`) ; activation à faire à la main.
- [ ] Cases « Inclure » décochées : application absente (nouvel Outlook, Outlook classique, OneDrive).
- [ ] Suppression (section 3) et installation (section 6) dans la même exécution : suppression d'abord, puis installation, aucune erreur.
- [ ] Le XML de l'installation figure dans le journal et dans `C:\ODT\configuration-installation-*.xml`.

## Itération 7 — Windows Update, journal, avancement, clé

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Windows Update : mises à jour (dont pilotes) téléchargées et installées sans fenêtre ; chaque titre et son résultat dans le journal ; « redémarrage nécessaire » dans le rapport ; aucun redémarrage automatique.
- [ ] Mises à jour restantes après la passe : ligne `[ATTN] … encore disponible(s)`.
- [ ] Pendant l'exécution : barre d'avancement et « Action n / N : … » sous le bouton Lancer.
- [ ] Clé protégée en écriture au démarrage, déprotégée avant la fin : journal et inventaire recopiés sur la clé (ligne « copiés sur la clé ») ; restée protégée : consigne de copie manuelle.
- [ ] `tools\Build-Usb.ps1 -Destination E:\FastPrepare` : avertissements de `config.json` affichés ; la clé ne contient que `Lancer.cmd`, `Preparation.ps1`, `config.json`, `src\`, `logos\`, `packages\`, `logs\`, `VERSION.txt` ; les anciens journaux de la clé sont conservés.

## Itération 8 — création d'une session locale (poste de test uniquement)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

Mot de passe d'essai à choisir pour la recette, **jamais** celui d'un vrai utilisateur.

- [ ] Section 11 décochée au démarrage ; cochée sans saisie : Lancer grisé (« nom de session vide »).
- [ ] Nom d'une session existante, nom actuel du poste, nom de 21 caractères, nom avec `/` ou `@`, nom terminé par un point : refusés avec leur motif sous le formulaire et sous Lancer.
- [ ] Nom d'une session cochée en section 4 : accepté (elle est supprimée avant d'être recréée).
- [ ] Confirmation différente : Lancer grisé ; identique : Lancer actif.
- [ ] « N'expire jamais » et « Changer à la première ouverture » ne peuvent pas être cochés ensemble.
- [ ] Simulation : ligne `[SIMU] [ETAPE 14/14 · section 11] Session locale : New-LocalUser '<nom>' …` ; le mot de passe n'apparaît **nulle part** dans le fichier journal (recherche du texte saisi).
- [ ] Réel, utilisateur standard : session créée, membre du groupe Utilisateurs seulement (`net localgroup Utilisateurs`), ouverture de session possible avec le mot de passe saisi.
- [ ] Réel, administrateur + « changer à la première ouverture » : membre de Utilisateurs et Administrateurs ; Windows demande un nouveau mot de passe à la première ouverture.
- [ ] Mot de passe refusé par la stratégie du poste (ex. trop court si une longueur minimale est imposée) : action en rouge avec le motif de Windows, **aucune** session créée.
- [ ] Deuxième exécution avec la même saisie, sans relancer l'outil : action en échec « existe déjà », la session existante n'est pas modifiée.
- [ ] Le mot de passe n'apparaît pas dans le journal de l'exécution réelle.

## Itération 9 — catalogue des logiciels (onglet Réglages)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Onglet Réglages : la liste reprend `software.json` ; le chemin du fichier sur la clé est affiché.
- [ ] Nouveau logiciel winget (ex. 7-Zip, `7zip.7zip`) : identifiant interne déduit du libellé, commande affichée ; **Tester** → « Paquet trouvé : nom, version » ; rien n'apparaît dans « Applications installées » du poste.
- [ ] Identifiant winget inexistant → « introuvable dans la source » ; source `msstore` (ex. `9NR5B8GVVM13`) → paquet trouvé.
- [ ] Lien direct vers un installateur → « Lien valide : fichier de … Mo » ; lien vers une page web → refusé « page web » ; lien `http://` ou éditeur vide → Enregistrer grisé avec le motif.
- [ ] Modifier un champ après un test réussi → « Formulaire modifié depuis le dernier test » ; Enregistrer sans test → demande de confirmation.
- [ ] Enregistrer : la case apparaît aussitôt en section 8 (onglet Préparation), les cases déjà cochées gardent leur état ; `software.json` mis à jour, ancienne version dans `software.json.bak` ; ligne `[OK] Catalogue des logiciels : … ajouté` dans le journal.
- [ ] Retirer : confirmation, la case disparaît de la section 8.
- [ ] Clé protégée en écriture : « Catalogue non enregistré : la clé … est protégée en écriture », catalogue inchangé.
- [ ] Pendant une exécution : l'onglet Réglages est grisé.
- [ ] Exécution réelle sur poste de test : un logiciel winget et un logiciel par lien direct ajoutés depuis l'onglet sont installés ; lien direct avec un mauvais éditeur attendu → action en rouge « signature », rien n'est lancé.
- [ ] Relancer l'outil : les logiciels ajoutés sont toujours là ; `software.json` modifié à la main avec une erreur → refus au démarrage avec l'entrée fautive.
- [ ] `tools\Build-Usb.ps1` sur une clé déjà préparée : catalogue de la clé conservé (message) ; avec `-ReplaceSoftwareCatalog` : remplacé.

## Itération 10 — source winget (outil lancé avec un autre compte administrateur)

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

- [ ] Lancer `Lancer.cmd` en donnant les identifiants d'un **autre** compte administrateur que la session ouverte : au démarrage, ligne `[OK] Source winget accessible`, ou bien `[ATTN] Installations winget impossibles en l'état : …` avec le nom du compte et les commandes de réparation.
- [ ] Source inutilisable réparée par la mise à jour : lignes `[ATTN] Source winget inutilisable … mise à jour des sources` puis `[OK] Source winget réparée par la mise à jour`.
- [ ] Source irréparable automatiquement : le test d'un logiciel winget (onglet Réglages) affiche le message lisible (compte, `winget source reset --force`, `winget source update`), jamais « code de sortie -1978335217 » ; après ces deux commandes lancées à la main dans une invite administrateur de ce compte, puis redémarrage de l'outil : `[OK] Source winget accessible` et test réussi.
- [ ] L'outil ne lance jamais `winget source reset` de lui-même (journal, niveau `DEBUG` : seules des commandes `source update`).

## Itération 11 — réparation de la source winget sans intervention

Poste : ____________________ · Date : __________ · Version (`VERSION.txt`) : __________

Reproduire le défaut constaté : dans une invite administrateur ouverte avec le compte qui lancera l'outil,
`powershell -NoProfile -Command "Get-AppxPackage -Name Microsoft.Winget.Source | Remove-AppxPackage"`,
puis vérifier que `winget show --id Microsoft.VisualStudioCode --exact --source winget` échoue (`0x8a15000f`).

- [ ] Lancer l'outil avec ce compte : au démarrage, `[ATTN] Source winget inutilisable …`, `[ATTN] Installation du paquet de données de la source winget (… signature « CN=Microsoft Corporation » vérifiée …)`, puis `[OK] Source winget réparée par l'installation de son paquet de données` et `[OK] Source winget accessible`. Aucune commande tapée.
- [ ] Test d'un logiciel winget dans l'onglet Réglages : réussi.
- [ ] `Get-AppxPackage -Name Microsoft.Winget.Source` : présent ; `%ProgramData%\FastPrepare\cache\winget-source` ne contient plus `source.msix`.
- [ ] Sans réseau au démarrage : message « malgré la mise à jour des sources (installation de son paquet de données : …) », aucune erreur bloquante.

## Itération 12 — alignement sur le cahier du 14 novembre (simulation)

Avant la recette : `tools\Invoke-Lint.ps1` et `tools\Invoke-Tests.ps1` verts (itération écrite sans PowerShell).

- [ ] Poste au nom attribué par Windows (`DESKTOP-…` ou `LAPTOP-…`) : section 1 « Rappel : renommage du poste », nom affiché, pastille « Nom par défaut de Windows », consigne en orange. Lancer n'est **pas** grisé pour autant.
- [ ] Poste déjà renommé : pas de pastille, consigne en gris.
- [ ] Plus aucun champ ni case de renommage ; le plan (bouton Lancer en simulation) compte 13 étapes et ne contient aucune ligne « Rename-Computer ».
- [ ] Mémo et rapport final : « Renommage du poste puis redémarrage (avant l'outil) », « Connexion du compte 365 » ; plus de « Réinitialisation de Windows » ni d'« Activation d'Office ».
- [ ] Section 8 : Adobe Acrobat Reader, Google Chrome, Mozilla Firefox (français), 7-Zip cochés ; Claude décoché. Onglet Réglages : test des cinq entrées réussi (paquets trouvés).
- [ ] Clé préparée **avant** cette itération : `tools\Build-Usb.ps1` conserve son `software.json` ; `-ReplaceSoftwareCatalog` pour prendre le nouveau catalogue de base.

## Première vérification sous Windows (itérations 13 à 18)

L'analyse statique et tous les tests passent sous Windows PowerShell 5.1 dans l'intégration continue (GitHub Actions), y compris la construction complète de la fenêtre sans affichage. **La fenêtre n'a en revanche jamais été affichée à l'écran et aucune action n'a été faite en mode réel.** Sur un poste de test Windows :

- [ ] `tools\Invoke-Lint.ps1` : aucun constat.
- [ ] `tools\Invoke-Tests.ps1` (Pester 5, Windows PowerShell 5.1) : tout est vert, en particulier `tests\FastPrepare.UI\UiBuild.Tests.ps1` (construit toute la fenêtre sans l'afficher : XAML, sections, pages, profil) et `tests\FastPrepare.Infrastructure\NetworkDrives.Tests.ps1` (registre de test).
- [ ] `Lancer.cmd` en simulation : la fenêtre s'ouvre, le journal ne contient aucune ligne `ERREUR`.

Un échec de `UiBuild.Tests.ps1` donne le fichier XAML ou la section en cause : le corriger avant de poursuivre.

## Itération 13 — interface par étapes, 16:9 (simulation)

La fenêtre n'a pas pu être affichée pendant le développement : cette recette est le premier affichage réel.

- [ ] La fenêtre s'ouvre en 1280 × 720, sans erreur dans le journal ; menu latéral : connexion, poste détecté, six entrées numérotées, « Catalogue logiciels », « Vérifier et lancer », bandeau de mode.
- [ ] Page « Poste » affichée à l'ouverture ; « Suivant → » parcourt Nettoyage, Comptes et domaine, Installations, Système et réseau ; sur cette dernière le bouton devient « Vérifier et lancer → » ; « ← Précédent » absent sur la première page.
- [ ] Un clic dans le menu latéral ouvre la page correspondante ; l'entrée active est surlignée.
- [ ] Chaque section est dans la bonne page (Poste : rappel du renommage, N/S et MAC ; Nettoyage : logiciels installés, programmes Microsoft, sessions locales ; Comptes et domaine : session à créer ; Installations : utilitaire constructeur, Office, logiciels ; Système et réseau : MàJ, paramètres système) et aucun titre ne porte de numéro.
- [ ] Récapitulatif : résumé et liste des actions conformes aux cases cochées ; elle change si l'on revient modifier une étape. Journal lisible, bouton Lancer unique.
- [ ] Session à créer cochée avec un nom vide : ⚠ sur « Comptes et domaine » dans le menu, encadré rouge « À corriger avant de lancer » au récapitulatif, Lancer grisé.
- [ ] Câble réseau débranché : pastille rouge, motif « connexion internet non validée » au récapitulatif, Lancer grisé ; rebranché : tout se rétablit seul.
- [ ] Lancer en simulation : pages de saisie grisées pendant l'exécution, navigation possible, journal alimenté, barre d'avancement ; à la fin les pages redeviennent modifiables.
- [ ] Page « Catalogue logiciels » : ajout, test et enregistrement d'un logiciel ; il apparaît dans la page Installations.
- [ ] Fenêtre réduite à sa taille minimale (1100 × 620) puis agrandie en plein écran : rien n'est coupé, les pages défilent si besoin.

## Itération 15 — plusieurs sessions locales (poste de test uniquement)

- [ ] Étape « Comptes et domaine » : saisir une session, « Ajouter à la liste » : elle apparaît à droite avec son résumé (jamais le mot de passe), le formulaire se vide.
- [ ] « N'expire jamais » ou « ne peut pas changer » coché : « doit changer à la première ouverture » se décoche et se grise.
- [ ] Nom déjà pris sur le poste, nom déjà dans la liste, confirmation différente, description de plus de 48 caractères : refus avec le motif en rouge, rien n'est ajouté.
- [ ] Nom saisi mais non ajouté : ⚠ dans le menu, Lancer grisé avec le motif au récapitulatif.
- [ ] « Modifier » remet la session dans le formulaire (mot de passe à ressaisir) ; « Retirer » l'enlève.
- [ ] Mode réel, deux sessions (une Administrateurs, une Utilisateurs désactivée avec description) : les deux existent (`Get-LocalUser`), groupes, description, options conformes ; le journal ne contient aucun mot de passe.
- [ ] Mot de passe refusé par la stratégie du poste pour la première session : elle est en échec, la seconde est tout de même créée.

## Itération 16 — agent RMM et antivirus par lien (poste de test uniquement)

- [ ] Étape Installations, section « Agent RMM et antivirus » : lien NinjaOne `.msi` collé → « NinjaOne reconnu : msiexec /i … /qn /norestart » en vert ; lien Datto RMM → « Datto RMM reconnu ».
- [ ] Lien Bitdefender `setupdownloader_[…].exe` → « /bdparams /silent » ; lien ESET `PROTECT_Installer_…exe` → « --silent --accepteula ».
- [ ] Lien `http://`, page web, exécutable d'antivirus inconnu : motif en rouge, ⚠ sur « Installations », Lancer grisé.
- [ ] Simulation : le plan contient « Agent RMM — … » (étape 14) et « Antivirus — … » (étape 15).
- [ ] Mode réel, pour **chaque** console utilisée : l'agent apparaît dans la console, l'antivirus est installé et rattaché à la bonne société ; aucun redémarrage automatique ; le fichier est dans le cache sous son nom d'origine.
- [ ] Lien expiré ou injoignable : action en échec dans le journal, les étapes suivantes s'exécutent.
- [ ] Mémo et rapport final : plus de ligne RMM ni antivirus.

## Itération 17 — lecteurs réseau et imprimantes IP (poste de test uniquement)

- [ ] Étape « Système et réseau » : lecteur `P:` → `\\serveur\partage` avec libellé, « Ajouter à la liste » ; lettre d'un disque du poste, lettre déjà dans la liste, chemin sans `\\` : refus en rouge.
- [ ] Mode réel, outil lancé **dans la session de l'utilisateur** (élévation avec un compte administrateur différent) : `HKU\<SID de l'utilisateur>\Network\P` contient `RemotePath` ; après fermeture puis réouverture de session, `P:` apparaît dans l'Explorateur avec son libellé et s'ouvre.
- [ ] Aucune tâche planifiée, aucun script de connexion, aucun fichier ajouté sur le poste pour ce lecteur.
- [ ] Lecteur `P:` déjà connecté ailleurs pour cet utilisateur : action en échec, mappage existant intact.
- [ ] Pilote décompressé dans `C:\Drivers` : « Actualiser » liste ses `.inf` ; le choix d'un `.inf` propose ses modèles.
- [ ] Mode réel : imprimante créée (`Get-Printer`), port `IP_<adresse>`, pilote déclaré ; une page de test s'imprime.
- [ ] Deuxième imprimante du même modèle : ni pnputil ni Add-PrinterDriver ne sont relancés (journal).
- [ ] Imprimante du même nom déjà présente : action en échec, imprimante existante intacte.

## Itération 18 — jonction au domaine (poste et domaine de test uniquement)

- [ ] Étape « Comptes et domaine » : domaine vide → aucune action « Jonction » au récapitulatif. Domaine sans point, compte vide, mot de passe vide : motif en rouge, ⚠ dans le menu, Lancer grisé.
- [ ] « Tester » avec un domaine joignable et un compte valide : « Domaine trouvé : … », « Compte … accepté » ; la fenêtre reste réactive pendant le test. Mauvais mot de passe : « refusé ». Domaine inexistant ou DNS du poste incorrect : « Domaine introuvable ».
- [ ] Récapitulatif : « Jonction au domaine » est la **dernière** ligne du plan, quelles que soient les autres cases.
- [ ] Mode réel : le poste est joint (`(Get-CimInstance Win32_ComputerSystem).PartOfDomain` après redémarrage manuel), **aucun redémarrage automatique**, le rapport final demande le redémarrage ; l'objet ordinateur est dans le conteneur par défaut du domaine, sous le nom définitif du poste.
- [ ] Journal : aucun mot de passe ; le compte de jonction y figure.
- [ ] Poste déjà membre de ce domaine : « rien à faire ». Membre d'un autre domaine : action en échec, poste intact.
- [ ] Compte sans droit de jonction : action en échec avec le message de Windows, les autres actions ont été faites.

## Itération 14 — profils entreprise (simulation)

- [ ] Clé neuve : sélecteur « Profil entreprise » vide ; « Enregistrer » sans nom : message en rouge, rien n'est écrit.
- [ ] Remplir les étapes (programmes Microsoft, Office, logiciels, deux sessions, liens RMM et antivirus, un lecteur, une imprimante, domaine et compte), saisir un nom, « Enregistrer » : `profils\<nom>.json` est créé sur la clé.
- [ ] Ouvrir ce fichier dans un éditeur : **aucun mot de passe** (ni des sessions, ni du compte de jonction).
- [ ] « Nouveau » : nom vidé, étapes revenues à leur état de départ.
- [ ] Choisir le profil dans la liste : toutes les étapes sont pré-remplies ; les sessions portent « MOT DE PASSE À SAISIR », le mot de passe du domaine est vide, ⚠ sur « Comptes et domaine », Lancer grisé. « Modifier » chaque session, saisir son mot de passe, « Ajouter à la liste », saisir celui du domaine : Lancer se dégrise.
- [ ] Modifier un réglage puis « Enregistrer » sous le même nom : confirmation, puis le fichier est mis à jour (un seul fichier pour ce client).
- [ ] Fichier de profil abîmé à la main (JSON invalide) : il n'apparaît pas dans la liste, un avertissement est au journal, les autres profils restent utilisables.
- [ ] Clé protégée en écriture : « Enregistrer » affiche un message explicite, rien n'est perdu.
- [ ] `tools\Build-Usb.ps1` sur une clé qui contient des profils : ils sont conservés.
- [ ] Pendant une exécution : sélecteur et boutons de profil grisés.

## Itération 19 — analyse de disque (lecture seule, tout mode)

- [ ] Menu latéral : « Analyse de disque » sous « Catalogue logiciels » ; ni Précédent ni Suivant sur cette page ; pied « Outil en lecture seule ».
- [ ] Le disque `C:\` est proposé avec son espace libre ; « Analyser » : avancement (fichiers, taille, dossier en cours), la fenêtre reste réactive, puis bilan (taille, fichiers, dossiers, durée, dossiers illisibles).
- [ ] Arborescence : dossiers du plus gros au plus petit, part du dossier parent, taille, nombre de fichiers ; la flèche ou un double-clic déplie et replie ; les petits fichiers sont regroupés (« 12 fichiers .dll »).
- [ ] Types de fichiers : classés par volume, une couleur par type, identique sur la carte.
- [ ] Carte : un clic sur une tuile la retrouve dans l'arborescence (dossiers dépliés, ligne sélectionnée, contour blanc) ; le survol affiche son chemin et sa taille ; la sélection d'un type entoure toutes ses tuiles.
- [ ] « Arrêter » pendant l'analyse : arrêt en une ou deux secondes, « Analyse interrompue (résultat partiel) ».
- [ ] Chemin d'un dossier saisi à la main : analysé ; chemin inexistant : message en rouge, rien d'autre ne change.
- [ ] « Ouvrir dans l'Explorateur » : dossier ouvert, ou fichier sélectionné dans son dossier.
- [ ] Fenêtre agrandie puis réduite : la carte se redessine à la nouvelle taille.
- [ ] Pendant une exécution (Lancer) : la page reste utilisable ; après l'analyse, aucun fichier ni réglage du poste n'a changé.

## Recette complète avant passage en mode réel par défaut (DEC6)

Dérouler, sur un poste de test réinitialisé de **chaque marque**, une exécution réelle **complète** (toutes les sections utiles cochées), puis :

- [ ] Rapport final sans échec inattendu ; échecs attendus compris et documentés.
- [ ] Après redémarrage manuel : Office installé et non activé, utilitaire constructeur présent, aucune application Microsoft retirée ne revient pour un nouveau profil.
- [ ] Deuxième exécution sur le même poste : tout est « déjà fait / déjà absent », aucune erreur.
- [ ] Valeurs provisoires confirmées ou corrigées dans `config.json` : codes de sortie winget et outils constructeurs (QO4), chemins `HPImageAssistant.exe` / `ducmd.exe`, lien et empreinte de Thin Installer.
- [ ] Alors seulement : `Execution.DefaultMode` = `"Real"` dans `config.json`.
