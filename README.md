# FastPrepare — Outil de préparation de poste Windows 11

Prépare un poste Windows 11 en une seule exécution, depuis une clé USB, une fois le poste
renommé et redémarré à la main : le technicien coche les actions dans une fenêtre, clique sur **Lancer**,
lit le journal, puis redémarre lui-même le poste. Applicable à n'importe quel parc :
tout ce qui varie d'un parc à l'autre se règle dans `config.json` (écrit à la main) et, pour les
logiciels proposés en section 8, dans `software.json` (modifié depuis l'onglet **Réglages**).

> **État : itération 12 (alignement sur le cahier du 14 novembre 2026, non encore vérifiée par les tests) ; itération 9 : toutes les étapes du cahier disponibles en mode réel, plus la création
> d'une session locale (section 11) et le catalogue des logiciels modifiable dans l'onglet Réglages.** La simulation
> reste le mode par défaut jusqu'à la recette complète sur postes de test
> ([`docs/recette.md`](docs/recette.md)) ; ensuite, `Execution.DefaultMode` = `"Real"` dans `config.json`.
> Feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md) §9.

## Pour le technicien

1. Préparer la clé depuis un poste de développement : `tools\Build-Usb.ps1 -Destination E:\FastPrepare`.
   Le script lance d'abord l'analyse statique et les tests : il faut PSScriptAnalyzer et Pester 5
   sur ce poste (`-PesterPath <dossier de Pester>` si Pester n'est pas installé, `-SkipChecks` pour
   ne pas les lancer). Pour les postes sans winget, placer au préalable le paquet hors ligne
   `Microsoft.DesktopAppInstaller.msixbundle` dans `packages\` (chemin : `Winget.OfflineBundle`).
2. Sur le poste à préparer : double-cliquer `Lancer.cmd` (demande les droits administrateur).
3. Suivre les étapes du menu de gauche (Poste, Nettoyage, Comptes et domaine, Installations,
   Système et réseau) avec **Suivant →**, puis relire le **Récapitulatif** et cliquer **Lancer**.
4. Lire le journal du récapitulatif ; il est aussi enregistré dans `logs\` sur la clé,
   avec l'inventaire N/S + adresses MAC. Si la clé est protégée en écriture, ils sont écrits
   dans `%TEMP%\FastPrepare` puis recopiés sur la clé en fin d'exécution si elle est redevenue
   accessible (sinon le rapport final indique de les copier à la main).

Une clé préparée avant l'itération 9 (`ConfigVersion` 2) est refusée au démarrage avec un message
explicite : la préparer de nouveau avec `tools\Build-Usb.ps1`.

Options : `Lancer.cmd -Simulation` (force la simulation), `Lancer.cmd -Real` (modifie le poste,
après confirmation ; bandeau rouge « MODE RÉEL »). Pendant l'exécution, la barre sous **Lancer** (page Récapitulatif)
indique l'action en cours ; la fenêtre ne redémarre jamais le poste.

Sessions locales (étape « Comptes et domaine ») : pour chacune, nom, nom complet, description,
groupe (Utilisateurs ou Administrateurs), mot de passe saisi deux fois et options (n'expire jamais,
à changer à la première ouverture, non modifiable par l'utilisateur, compte désactivé), puis
« Ajouter à la liste ». Les mots de passe ne sont jamais écrits dans le journal ni sur la clé ;
une session existante n'est jamais modifiée.

Page **Catalogue logiciels** : ajouter un logiciel proposé à l'étape Installations, par
paquet winget ou par lien direct (`.exe` / `.msi`), le **tester sans rien télécharger ni installer**
(paquet trouvé, lien qui mène bien à un fichier), puis l'enregistrer dans `software.json` sur la clé.
`tools\Build-Usb.ps1` conserve le catalogue déjà présent sur une clé (`-ReplaceSoftwareCatalog` pour
le remplacer par celui du dépôt).

Agent RMM et antivirus (étape Installations) : coller le lien fourni par la console (NinjaOne,
Datto RMM, Bitdefender, ESET) ; l'outil reconnaît l'installateur, le télécharge, vérifie sa
signature et l'installe en silencieux. Champ vide : rien n'est installé.

Lecteurs réseau et imprimantes IP (étape « Système et réseau ») : les lecteurs sont connectés de
façon persistante pour l'utilisateur de la session ouverte (visibles à sa prochaine ouverture de
session, sans script ni tâche planifiée) ; pour une imprimante, déposer d'abord son pilote
décompressé dans `C:\Drivers` (`Printers.DriverFolder` dans `config.json`), puis choisir le
fichier `.inf` et le modèle.

Jonction au domaine (étape « Comptes et domaine ») : domaine, compte autorisé et mot de passe,
bouton **Tester** (rien n'est modifié). La jonction est toujours la dernière action ; elle devient
effective au redémarrage final, à faire à la main. Domaine vide : pas de jonction.

**Fait à la main, hors outil** : renommage du poste suivi d'un redémarrage (avant l'outil : le
nouveau nom n'est effectif qu'après redémarrage, DEC22), BitLocker, connexion du compte 365, redémarrage final (liste dans `config.json`, `ManualReminders`).
L'étape « Poste » rappelle le renommage et signale un poste qui porte encore le nom donné par Windows.

## Profils entreprise

Les réglages propres à un client (programmes Microsoft à retirer, Office, logiciels, sessions
locales, liens RMM et antivirus, lecteurs réseau, imprimantes, domaine) s'enregistrent dans un
**profil** : remplir les étapes, saisir le nom du client dans « Profil entreprise » (menu de
gauche), **Enregistrer**. Le profil est écrit sur la clé dans `profils\<nom>.json` ; le choisir
dans la liste pré-remplit toutes les étapes sur le poste suivant. **Nouveau** remet les étapes
dans leur état de départ.

Un profil ne contient **jamais de mot de passe** : ceux des sessions locales et du compte de
jonction au domaine sont saisis à chaque préparation. Il contient en revanche les liens RMM et
antivirus du client : garder la clé comme un support interne.

## Adapter l'outil à un parc

`config.json` et `software.json` sont validés au démarrage, avec un message qui indique la clé
ou l'entrée fautive :

| Besoin | Clé |
|---|---|
| Ajouter une marque (card de la section 5) | `Utilities.<clé>` + logo facultatif dans `logos\` |
| Changer un identifiant winget, un lien, une version | `Utilities`, `Office` |
| Ajouter, modifier, retirer un logiciel à installer (section 8) | onglet **Réglages** de la fenêtre (enregistré dans `software.json`) |
| Ajouter une édition Office | `Office.Editions[]` |
| Durées d'alimentation, batterie incluse ou non | `Power` |
| Rappels des actions manuelles | `ManualReminders` |
| Mode par défaut (simulation ou réel) | `Execution.DefaultMode` |
| Options proposées par défaut pour la session à créer (section 11) | `NewLocalAccount` (facultatif) |

## Pour le développeur

- Architecture, responsabilités par fichier, règles et feuille de route : [`docs/architecture_plan.md`](docs/architecture_plan.md).
- Conventions, tests, lint : [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
- Ajouter une étape d'exécution : un fichier `src\FastPrepare.Application\Steps\<Nom>.step.ps1` + son rang dans `StepOrder.ps1` (plan, §10.1).
- Ajouter un réglage à l'onglet Réglages : une section `Register-UiSection -Column Settings` (plan, §10.6).
- Recette manuelle sur poste réel : [`docs/recette.md`](docs/recette.md).

```text
Lancer.cmd → Preparation.ps1 → src\FastPrepare.UI → src\FastPrepare.Application → src\FastPrepare.Infrastructure
                                                                          └──────────► src\FastPrepare.Core (règles pures)
```
