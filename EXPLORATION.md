# Exploration — TP2 DermaScan

## Question 0.1
> Pourquoi décider du rappel visé avant la première mesure ?

Rappel visé retenu : **0,90**, soit au plus une lésion maligne manquée sur dix.
C'est un besoin métier (outil de tri : rater un cancer coûte bien plus cher qu'un
examen inutile), pas un résultat d'expérience. Si on le fixait après avoir vu la
courbe rappel/précision, on choisirait le seuil qui « fait joli » sur l'ensemble de
test : le test servirait alors à régler le modèle, et la performance annoncée serait
optimiste. Le décider avant garde le test honnête et rend le choix défendable.

## Mesure 1 — versions et volumétrie
| Relevé | Valeur |
|---|---|
| Version de Python | 3.11.5 |
| Version de scikit-learn | 1.9.1 |
| Version de pandas | 3.0.6 |
| Poids du fichier d'annotation | 246 Mo |

## Mesure 2 — volumétrie et structure
| Relevé | Valeur |
|---|---|
| Nombre de lignes | 401 059 |
| Nombre de colonnes | 55 |
| Nombre de patients distincts | 1 042 |
| Lésions par patient : min / médiane / max | 1 / 241 / 9 184 |

### Question 1.1
Il y a 401 059 lignes mais seulement 1 042 patients, soit en médiane 241 lésions par
patient. Les lignes d'un même patient ne sont pas indépendantes : même peau, même âge,
même appareil, même photographe. Le modèle peut apprendre à reconnaître le patient
plutôt que la lésion. La taille réelle de l'échantillon est donc le **nombre de
patients (1 042)**, et c'est par patient qu'il faut découper train/test.

## Mesure 3 — colonnes de fuite
| Colonne | Valeurs renseignées | Dont malignes | Écartée ? |
|---|---|---|---|
| iddx_1 | 401 059 | 393 (100 %) | Oui |
| iddx_full | 401 059 | 393 (100 %) | Oui |
| mel_thick_mm | 63 | 63 (16 % des malignes) | Oui |
| mel_mitotic_index | 53 | 53 (13 % des malignes) | Oui |
| lesion_id | 22 058 | 393 (100 %) | Oui |

(iddx_2 à iddx_5 aussi écartées : 1 068 / 1 065 / 551 / 1 valeurs.)

### Question 1.2
`lesion_id` n'est renseigné que pour 22 058 lésions sur 401 059, mais **les 393
malignes en ont toutes un**. Sa seule présence signale donc « cette lésion a été
retenue pour un suivi ou une biopsie ». Cet identifiant est attribué **après** que le
dermatologue a jugé la lésion suspecte, donc après le moment où le modèle doit
décider : il n'existera pas pour une nouvelle lésion.

### Question 1.3
`iddx_1` est le résultat du diagnostic (histopathologie) : le modèle n'apprend pas à
reconnaître un cancer, il recopie la réponse qu'on lui donne. Le jour où une nouvelle
lésion arrive, cette colonne est vide puisque le diagnostic n'est pas encore fait, et
le score de 100 % s'effondre.

## Mesure 4 — manquantes et constantes
| Relevé | Valeur |
|---|---|
| Colonnes avec valeurs manquantes (hors fuites) | sex, anatom_site_general, age_approx |
| Taux de manquantes pour chacune | 2,87 % / 1,44 % / 0,70 % |
| Colonnes constantes | image_type |
| Variables restantes | 40 (35 numériques, 5 catégorielles) |

Retirées en plus : identifiants (`isic_id`, `patient_id`) et administratives
(`attribution`, `copyright_license`), qui décrivent la provenance de l'image et non la lésion.

### Question 1.4
On la retire explicitement pour que la liste des variables attendues par l'API soit
courte et exacte : sinon chaque client devrait envoyer un champ qui ne sert à rien.
On consigne son existence parce qu'elle est constante **dans ce jeu** seulement : si
la production envoie un autre type d'image, c'est un changement de données à détecter,
et il faut savoir que le modèle n'a jamais vu de variation sur ce point.

## Mesure 5 — déséquilibre de la cible
| Relevé | Valeur |
|---|---|
| target = 1 | 393 |
| target = 0 | 400 666 |
| Taux de positifs | 0,098 % |
| Une maligne pour N bénignes | 1 020 |

### Question 1.5
Répondre « bénin » partout donne 400 666 / 401 059 = **99,90 %** d'exactitude, sans
jamais trouver un seul cancer. L'exactitude est donc inutile comme critère de choix
ici : avec une classe aussi rare, elle mesure surtout la proportion de bénins.
