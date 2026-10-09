# Model card — DermaScan triage v1.0.0

## Usage prévu
Aide au **tri** des lésions cutanées photographiées par un système d'imagerie corps entier
(3D-TBP) : le modèle signale les lésions qui méritent l'examen d'un dermatologue. Il
s'utilise sur les métadonnées tabulaires de la lésion (taille, couleur, contour, symétrie,
position, âge, sexe), en amont de l'avis médical.

## Usage explicitement exclu
- Poser un diagnostic, ou rassurer un patient : une absence d'alerte ne vaut pas bénignité.
- Décider seul d'une biopsie ou d'un renoncement à l'examen.
- S'appliquer à des photos de smartphone, à la dermoscopie seule ou à un autre appareil
  que celui de l'entraînement (variables `tbp_lv_*` propres au système 3D-TBP).
- S'appliquer à une population très différente de celle d'entraînement (voir plus bas)
  sans réévaluation.

## Données d'entraînement
ISIC 2024 (SLICE-3D), fichier `train-metadata.csv` : **401 059 lésions, 1 042 patients**,
7 institutions (États-Unis, Espagne, Suisse, Australie, Autriche, Grèce). **393 malignes, soit
0,098 %** (une pour 1 020 bénignes). Cette prévalence est celle d'un dépistage corps entier,
où toutes les lésions d'un patient sont photographiées : elle est bien plus faible que dans
une consultation où l'on n'adresse que les lésions déjà jugées suspectes.
Découpage par patient (`GroupShuffleSplit`, 20 % des patients en test, graine 42) :
319 514 lésions (833 patients) en entraînement, 81 545 (209 patients, 110 malignes) en test.

## Variables utilisées
**40 variables** : 35 numériques et 5 catégorielles.
- Taille et forme : `clin_size_long_diam_mm`, `tbp_lv_areaMM2`, `tbp_lv_minorAxisMM`,
  `tbp_lv_perimeterMM`, `tbp_lv_area_perim_ratio`, `tbp_lv_eccentricity`.
- Couleur et contraste avec la peau voisine : `tbp_lv_A/B/C/H/L` et leurs versions `ext`,
  `tbp_lv_delta*`, `tbp_lv_color_std_mean`, `tbp_lv_stdL*`, `tbp_lv_radial_color_std_max`,
  `tbp_lv_norm_color`.
- Contour et symétrie : `tbp_lv_norm_border`, `tbp_lv_symm_2axis`, `tbp_lv_symm_2axis_angle`.
- Position : `anatom_site_general`, `tbp_lv_location`, `tbp_lv_location_simple`, `tbp_lv_x/y/z`.
- Patient : `age_approx`, `sex`.
- Scores de l'appareil : `tbp_lv_nevi_confidence`, `tbp_lv_dnn_lesion_confidence`, `tbp_tile_type`.

Prétraitements dans le pipeline : imputation (médiane, ou modalité la plus fréquente),
standardisation, encodage one-hot avec `handle_unknown="ignore"`. Modèle : régression
logistique avec `class_weight="balanced"`.

## Variables écartées, avec le motif
| Variables | Motif |
|---|---|
| `iddx_full`, `iddx_1` à `iddx_5` | **Fuite** : diagnostic histopathologique, connu après la biopsie |
| `mel_thick_mm`, `mel_mitotic_index` | **Fuite** : mesures faites sur un mélanome déjà excisé |
| `lesion_id` | **Fuite** : attribué seulement aux lésions retenues pour suivi ; les 393 malignes en ont toutes un |
| `isic_id`, `patient_id` | Identifiants. `patient_id` sert uniquement au découpage |
| `attribution`, `copyright_license` | Administratives : provenance de l'image, pas une mesure de la lésion |
| `image_type` | Constante dans tout le jeu |

## Performance (ensemble de test, patients jamais vus)
| Modèle | Exactitude | ROC-AUC | PR-AUC |
|---|---|---|---|
| Référence « toujours bénin » | 99,87 % | 0,500 | 0,0013 |
| **Régression logistique** | 84,90 % | **0,910** | **0,054** |

La PR-AUC vaut environ 40 fois celle du hasard (0,0013), mais reste loin de 1 : le modèle
trie, il ne diagnostique pas. Avec 110 malignes en test, ces chiffres varient d'une graine à
l'autre.

## Seuil et compromis
Rappel visé, fixé avant toute mesure : **0,90**, soit un **seuil de 0,3476**.
- Rappel obtenu : 0,900, soit 11 malignes manquées sur 110.
- Précision : 0,51 %, soit environ **198 lésions examinées pour trouver une maligne**.
- **240 alertes pour 1 000 lésions**, soit environ une lésion sur quatre adressée au dermatologue.

### Question 5.1
Non, le seuil ne reste pas valable tel quel. À rappel et taux de faux positifs inchangés
(environ 24 %), passer de 0,1 % à 5 % de malignes ferait monter la précision d'environ 0,5 % à
environ 16 % (une maligne pour 6 alertes au lieu d'une pour 198). Le compromis présenté au
médecin-chef ne serait donc plus le bon. Surtout, une consultation spécialisée ne voit pas
les mêmes lésions : les bénignes y sont déjà jugées suspectes, donc plus difficiles à
distinguer des malignes, et le rappel réel à ce seuil est inconnu. Il faudrait refaire
l'évaluation sur un échantillon étiqueté issu de cette consultation : recalculer la courbe
rappel/précision, recalibrer les probabilités sur la nouvelle prévalence, puis choisir à
nouveau le seuil à partir du rappel visé, décidé avant la mesure.

### Question 5.2
Je refuserais de garantir les performances pour les **patients à peau foncée
(phototypes V et VI) et, plus largement, pour ceux pris en charge hors des pays
représentés**. La colonne `attribution` montre que les 401 059 lésions viennent de 7
institutions situées aux États-Unis, en Europe et en Australie. Les deux plus grosses,
Memorial Sloan Kettering (129 068) et Hospital Clínic de Barcelona (105 724), en portent à elles
seules 58 %. Aucune ne se trouve en Afrique, en Asie ou en Amérique latine, et le jeu ne
contient pas de colonne de phototype pour vérifier leur représentation. Or les variables de
couleur et de contraste, centrales pour le modèle, dépendent directement de la couleur de
peau. Même prudence pour une institution peu représentée : Athènes n'a que 7 976 lésions,
soit 2 % du jeu.

## Populations et angles morts
- Peaux foncées et centres hors États-Unis, Europe et Australie : absents ou non mesurables (voir 5.1 et 5.2).
- Données manquantes : `sex` 2,9 %, `anatom_site_general` 1,4 %, `age_approx` 0,7 % ; elles sont imputées.
- Positions anatomiques nouvelles : ignorées à l'encodage, donc prédiction avec une information en moins.
- Changement d'appareil ou de version du logiciel 3D-TBP : les variables `tbp_lv_*` peuvent changer de sens.

## Versions
| Élément | Valeur |
|---|---|
| Modèle | 1.0.0, entraîné le 2026-10-09 |
| Paquet | `model/modele.joblib` (9,9 Ko) |
| Image | `acrdermascankorich.azurecr.io/dermascan-api:1.0.0` |
| Digest | `sha256:d979c792ceb0652b7aff980ffa2be335a207396032392560150b470316ba8ff0` |
| Bibliothèques (épinglées) | Python 3.11, scikit-learn 1.9.1, numpy 2.4.6, pandas 3.0.6, joblib 1.6.0, scipy 1.17.1, Flask 3.1.3, gunicorn 26.2.0 |
