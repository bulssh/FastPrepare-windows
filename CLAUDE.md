# CLAUDE.md — reprise du projet dans Claude Code

Ce fichier est lu au début de chaque session Claude Code. Il résume tout ce qu'il faut savoir pour
continuer le projet sans l'historique des conversations précédentes. Les détails sont dans
`docs/architecture_plan.md` (plan, décisions DEC1 à DEC27, journal des itérations), `docs/recette.md`
(recettes manuelles) et `docs/CONTRIBUTING.md` (règles de code). En cas de doute, ces documents font foi.

## Le projet

Outil **universel** de préparation de postes Windows 11, lancé depuis une clé USB par un technicien :
interface WPF en Windows PowerShell 5.1, composants natifs uniquement (winget autorisé), **mode réel
par défaut** depuis le 17 novembre 2026 (DEC6, après les recettes en mode réel), `Lancer.cmd -Simulation`
pour un essai à blanc. Il ne cite aucun client ni aucune entreprise : aucun nom de client dans le
code, la documentation, les profils d'exemple ou les messages.

Le dépôt a été repris à neuf (un seul commit de départ) à partir d'une base existante. Il est
**totalement indépendant** de tout autre dépôt : ne jamais ajouter d'autre `remote`, ne jamais citer ni
contacter un autre dépôt, ne jamais réintroduire d'ancien historique.

## Façon de travailler avec Yanis (propriétaire du projet)

- Répondre en **français**.
- **Une étape à la fois** ; ne rien supposer sans lui demander. Pour une décision qui peut aller dans
  les deux sens, poser la question avant d'agir.
- Il est l'**exécutant** : quand une action doit être faite par lui (dans la VM, sur GitHub, sur son
  poste), lui donner l'instruction exacte et attendre son retour.
- Dans tout tableau récapitulatif, mettre les **liens directement dans le tableau**.
- Dire clairement ce qui a été vérifié et ce qui ne l'a pas été.

## Règles de fond (ne pas les assouplir sans son accord)

- **Jamais de redémarrage automatique** (ni dans l'outil, ni par un installateur : `/norestart`).
- **Mots de passe** : saisis à chaque préparation, en `SecureString` de bout en bout ; jamais écrits
  sur la clé, dans un profil, dans le journal ni dans un fichier (DEC15, DEC27). La lecture d'un mot
  de passe en clair est interdite (`tests/Architecture.Tests.ps1`).
- **Renommage du poste** : fait à la main avant l'outil ; l'outil n'affiche qu'un rappel (DEC22).
- **À la main, hors outil** : BitLocker, connexion du compte 365, redémarrage final.
- **Échec d'une étape** : écrit au journal, l'exécution continue avec les suivantes.
- **Coupure d'internet** : `ERREUR` seulement au-delà de `Connectivity.GraceSeconds` (DEC28).
- **Codes de sortie des utilitaires constructeur** : sens dans `Update.ExitCodeMessages`, seulement
  d'après la documentation de l'éditeur (DEC29).
- **Jonction au domaine** : toujours la dernière action, sans redémarrage, pas de champ OU (DEC26).
- **Lecteurs réseau** : mappage persistant écrit dans la ruche de l'utilisateur de la session
  ouverte ; **aucun script ni tâche planifiée laissés sur le poste** (DEC25).
- `config.json` est écrit à la main, jamais par l'outil (DEC17) ; les profils `profils\*.json` sont
  écrits par l'outil, sans mot de passe (DEC27). `profils\` n'est pas versionné (liens RMM et
  antivirus propres à un client).
- Office : ODT dans `C:\ODT`, XML généré à la volée. Utilitaires constructeur : Dell, HP, Lenovo,
  Fujitsu uniquement. Logiciels de base : Adobe Reader, Chrome, Firefox (fr), 7-Zip, Claude.

## Architecture en bref

Quatre modules dans `src/` (couches vérifiées par les tests) : `FastPrepare.Core` (règles pures),
`FastPrepare.Infrastructure` (seul accès au système), `FastPrepare.Application` (étapes, plan,
moteur), `FastPrepare.UI` (WPF : coquille `MainWindow`, une section par fragment XAML).
Le parcours de l'interface est décrit dans `Core/Public/Wizard.ps1` : Poste, Nettoyage, Comptes et
domaine, Installations, Système et réseau, Récapitulatif (seul bouton Lancer), puis hors parcours :
Catalogue logiciels et Analyse de disque (outil en lecture seule, itération 19).
18 étapes d'exécution, ordre dans `Application/StepOrder.ps1`. Recettes pour ajouter une étape, une
section, un logiciel : `docs/architecture_plan.md` §10.

## Commandes

| Commande | Rôle |
|---|---|
| `tools\Invoke-Lint.ps1` | PSScriptAnalyzer + encodages (doit être sans constat) |
| `tools\Invoke-TestsCi.ps1` | Tous les tests, un processus par fichier, délai maximal (méthode recommandée) |
| `tools\Invoke-Tests.ps1` | Tous les tests dans un seul processus |
| `tools\Invoke-VmCheck.ps1` | Sur un poste de test : relevé réel en lecture, simulation complète, construction de la fenêtre ; écrit `resultat-vm.txt` |
| `Lancer.cmd -Simulation` | L'outil, sans rien modifier (**toujours ce mode-là hors VM** : sans paramètre, l'outil s'ouvre en mode réel) |

L'intégration continue (`.github/workflows/ci.yml`, Windows PowerShell 5.1) lance les trois premières
à chaque envoi sur `main`. État au 15 novembre 2026 : **tout est vert** (1 760 tests, lint sans constat,
vérification sans fenêtre réussie).

## Pièges déjà rencontrés

- Sous 5.1, `@($liste)` sur une `System.Collections.Generic.List[object]` lève « Argument types do not
  match » : utiliser `.ToArray()`.
- PowerShell ne distingue pas la casse des variables : une variable locale `$account` écrase le
  paramètre `$Account`. Nommer différemment.
- **Un test ne doit jamais agir sur le poste qui l'exécute** : tout appel système est simulé (un test
  lançait autrefois une vraie recherche Windows Update). En cas de doute, lancer les tests dans la VM.
- Encodages : `.ps1/.psm1/.psd1` en UTF-8 **avec BOM** et CRLF ; `.xaml/.json/.md` en CRLF sans BOM.
- WPF ne s'affiche pas à travers SSH (pas de bureau) : la construction de la fenêtre se teste avec
  `New-MainWindow` (sans affichage) ; l'affichage réel se vérifie dans la console de la VM.

## Machine virtuelle de test

- Windows 11, accessible en SSH depuis le poste de Yanis : `admin@192.168.56.103` (réseau privé hôte
  VirtualBox). **Le mot de passe n'est jamais écrit dans le dépôt ni dans un fichier** : le demander à
  Yanis ou passer à une authentification par clé.
- Elle a été montée rapidement : Yanis a demandé de la **sécuriser si besoin**. Proposer (et faire
  après son accord) : authentification SSH par clé, mot de passe changé, connexion par mot de passe
  désactivée, SSH limité au réseau privé hôte.
- Avant tout test en **mode réel**, prendre un instantané VirtualBox (`VBoxManage snapshot`) et le
  restaurer ensuite. Ne jamais lancer le mode réel ailleurs que dans la VM.

## Suite du travail (dans l'ordre, une étape à la fois)

Fait au 17 novembre 2026 : vérification dans la VM, sécurisation, recette d'affichage en simulation,
analyse de disque (itération 19), recettes en mode réel des 16 et 17 novembre (toutes les étapes sauf
RMM et antivirus), passage du mode par défaut en réel, `actions/checkout` en v5.

1. Recette sur de vrais postes de chaque marque (`docs/recette.md`, « Recette complète sur postes de
   marque ») : codes de sortie des utilitaires (QO4), chemin de `ducmd.exe`.
2. Points ouverts : options silencieuses RMM et antivirus à confirmer avec de vrais liens ; lien Lenovo
   Thin Installer vide dans `config.json` ; paquet winget de Claude installé pour l'utilisateur seulement ;
   le cahier des charges (hors dépôt) n'intègre pas encore DEC23 à DEC29.
3. Ménage GitHub (par Yanis) : supprimer les branches `livraison` et `iteration-12` à `iteration-18`,
   qui pointent toutes sur le commit de départ ; seule `main` sert.

## Commits

Conventional Commits en français, une branche par sujet fusionnée dans `main`. Lint et tests verts
avant chaque envoi.
