# Mesures — TP2 DermaScan

## Tableau de décisions
| Décision | Valeur |
|---|---|
| Suffixe personnel | korich |
| Groupe du registre | rg-dermascan-registre-korich |
| Nom du registre ACR | acrdermascankorich (acrdermascankorich.azurecr.io, région Belgium Central) |
| Rappel visé (décidé avant tout résultat) | 0,90 |
| Date de l'étiquette a_detruire | 2026-12-31 |

## Mesure 6 — découpage (GroupShuffleSplit par patient, graine 42, 20 % des patients en test)
| Relevé | Entraînement | Test |
|---|---|---|
| Lignes | 319 514 | 81 545 |
| Patients | 833 | 209 |
| Positifs | 283 | 110 |
| Taux de positifs | 0,0886 % | 0,1349 % |

Intersection des patients entre entraînement et test : 0 (vérifiée par `assert`).

### Question 2.1
Non : 0,089 % en entraînement contre 0,135 % en test, soit 1,5 fois plus de malignes
en test. `GroupShuffleSplit` tire des patients au hasard sans regarder la cible ;
quand toute la classe rare tient en 393 cas, concentrés chez quelques patients, un
seul patient avec beaucoup de malignes suffit à déséquilibrer les deux côtés.
Conséquence : les scores (PR-AUC surtout) **varient sensiblement d'une graine à
l'autre**, et un chiffre obtenu avec une seule graine est à présenter avec prudence.

### Question 2.2
Avec `handle_unknown="error"`, une position anatomique inconnue fait planter la
prédiction (`ValueError: Found unknown categories`, donc une erreur 500).
Avec `handle_unknown="ignore"`, la catégorie inconnue est encodée comme « aucune des
catégories connues » (que des zéros) et la prédiction se fait avec les autres
variables. Pour un service de tri médical je retiens **`ignore`** : une lésion non
évaluée parce qu'un libellé a changé est pire qu'une lésion évaluée avec une
information en moins (et l'événement doit être journalisé pour être corrigé).

### Question 2.3
Imputer avant le découpage calculerait les médianes et les modalités les plus
fréquentes sur tout le tableau : des **statistiques de l'ensemble de test entreraient
dans le modèle**, ce qui est une fuite et rend l'évaluation optimiste.

## Mesure 7 — comparaison des modèles (test)
| Modèle | Exactitude | ROC-AUC | PR-AUC |
|---|---|---|---|
| DummyClassifier | 99,87 % | 0,5000 | 0,0013 |
| Régression logistique | 84,90 % | 0,9097 | 0,0541 |
| Hasard (PR-AUC) | — | — | 0,0013 |

### Question 2.4
Selon l'exactitude, le **DummyClassifier gagne** (99,87 % contre 84,90 %). En réalité
c'est la **régression logistique** qui est meilleure : elle trouve des cancers, le
Dummy n'en trouve aucun. L'exactitude compte les bonnes réponses toutes classes
confondues : elle est dominée par les 81 435 bénins du test et ne compte presque pas
les 110 malignes. Elle ne dit rien du nombre de cancers trouvés ou manqués. Avec
`class_weight="balanced"`, le modèle accepte beaucoup de fausses alertes pour trouver
les malignes : son exactitude baisse alors que son utilité augmente.

### Question 2.5
Taux de positifs du test : 110 / 81 545 = 0,001349, et PR-AUC du hasard = **0,0013** :
c'est bien la même valeur. La ROC-AUC mesure le taux de faux positifs par rapport aux
**81 435 bénins** : 1 % de faux positifs semble faible, mais cela fait 814 fausses
alertes, soit sept fois plus que de vraies malignes. La ROC-AUC (0,91) paraît donc
excellente. La PR-AUC regarde la **précision**, c'est-à-dire la part de vraies
malignes parmi les alertes, ce qui est exactement le coût vécu par le dermatologue :
0,054, soit environ 40 fois le hasard, mais loin de 1.

## Mesure 8 — compromis rappel / précision
| Seuil | Rappel | Précision | VP | FP | FN | Alertes / 1000 |
|---|---|---|---|---|---|---|
| 0,50 | 0,818 | 0,0073 | 90 | 12 290 | 20 | 151,8 |
| 0,80 | 0,618 | 0,0155 | 68 | 4 306 | 42 | 53,6 |
| 0,90 | 0,473 | 0,0218 | 52 | 2 338 | 58 | 29,3 |
| 0,99 | 0,182 | 0,0490 | 20 | 388 | 90 | 5,0 |

## Mesure 9 — seuil retenu
| Relevé | Valeur |
|---|---|
| Rappel visé | 0,90 |
| Seuil correspondant | 0,3476 |
| Rappel obtenu | 0,900 |
| Précision à ce seuil | 0,0051 |
| Lésions examinées par maligne trouvée | 198 |
| Faux négatifs restants | 11 (sur 110 malignes en test) |
| Alertes pour 1 000 lésions | 239,8 |

### Question 2.6
« Docteur, pour trouver 9 cancers sur 10, le service vous adresse environ **une
lésion sur quatre** (240 pour 1 000), et il faut en examiner **198 pour trouver une
maligne**. Il en laisse passer environ une sur dix (11 sur 110 dans notre test). »
S'il juge ce volume inacceptable, deux options : **baisser le rappel visé**, en
acceptant explicitement de rater plus de cancers (à 0,50 de seuil : 152 alertes pour
1 000 mais 2 malignes sur 10 ratées), ou **améliorer le modèle** (modèle plus
puissant, images). Ce n'est pas à moi de choisir seul : c'est un arbitrage clinique
entre charge de travail et cancers manqués, qu'il doit trancher.

### Question 2.7
Le service promet de signaler environ 90 % des lésions malignes qui ressemblent à
celles de l'entraînement ; il ne promet pas de les signaler toutes, et une absence
d'alerte ne vaut pas un diagnostic de bénignité.

## Mesure 10 — paquet
| Relevé | Valeur |
|---|---|
| Taille (Ko) | 9,9 |
| Colonnes attendues | 40 |
| Durée d'entraînement (s) | 13,60 |

Versions dans le paquet : Python 3.11.5, scikit-learn 1.9.1, pandas 3.0.6, numpy 2.4.6, joblib 1.6.0.

### Question 2.8
Le modèle a été entraîné avec 0,089 % de malignes. En séance 5, on comparera le
taux de malignes réellement confirmées (ou le taux d'alertes) du flux reçu avec cette
valeur de référence : s'il s'en écarte fortement, la population a changé, la
précision et le seuil ne sont plus valables, et il faut réévaluer ou réentraîner.
Sans la valeur stockée dans le paquet, on n'aurait rien à quoi comparer.

### Question 2.9
1. L'API ne peut pas **valider** la charge utile : impossible de répondre 400 en
   nommant les variables manquantes, la requête incomplète plante dans
   `predict_proba` et renvoie une erreur 500.
2. L'API ne peut pas construire le DataFrame **dans le bon ordre et avec les bons
   noms** de colonnes, et `/model/info` ne peut pas dire aux clients ce qu'ils doivent
   envoyer : il faudrait relire le code d'entraînement pour le savoir.

### Question 3.1
Mesures (`captures/chargement.txt`, `captures/chargement_chaud.txt`) :
- tout premier chargement après installation (imports à froid de scikit-learn, pandas, numpy) : 46 132 ms ;
- premier chargement dans un processus Python neuf (imports des sous-modules compris) : 3 960 ms ;
- chargement suivant, processus déjà chaud : **1,2 ms**.

Si l'API rechargeait le modèle à chaque requête dans un processus déjà démarré, elle
ajouterait environ 1,2 ms par appel, soit +14 % sur la latence médiane de 8,7 ms. Ce
n'est pas dramatique ici parce que le modèle pèse 10 Ko, mais le coût croît avec la
taille du modèle et se paie à chaque appel au lieu d'une seule fois. Surtout, si
chaque requête était servie par un processus neuf, elle paierait les ~4 s d'imports :
la latence serait multipliée par environ 450. Charger une fois au démarrage fait
payer ce coût une seule fois.

## Mesure 11 — réponses de l'API
| Appel | Code HTTP | Élément relevé |
|---|---|---|
| GET /health | 200 | model_loaded = true, version 1.0.0 |
| GET /model/info | 200 | colonnes attendues = 40, seuil 0,3476, rappel cible 0,9 |
| POST /predict (valide) | 200 | proba = 0,0314 / décision = pas_d_alerte |
| POST /predict (incomplète) | 400 | 20 variables manquantes signalées (10 premières listées) |
| POST /predict (corps vide) | 400 | « corps JSON absent ou invalide : objet attendu » |
| GET /health sans modèle (Q 3.3) | 503 | model_loaded = false, FileNotFoundError |

### Question 3.2
Une décision seule (« pas d'alerte ») est invérifiable une fois que le seuil a
changé. Avec la **probabilité**, le **seuil** et le **rappel visé** dans la réponse,
le dermatologue (ou un audit) peut savoir dans six mois sur quelle règle la décision
reposait, recalculer la décision avec un nouveau seuil, et voir si un cas était
limite (0,34 contre un seuil de 0,35) ou franc. La décision devient traçable et
reproductible.

## Mesure 12 — latence (10 appels)
min 8,4 ms · médiane 8,8 ms · max 25,4 ms

(Le maximum est probablement le premier appel, avant que le processus soit « chaud ».)

### Question 3.3
Sans modèle, `/health` renvoie **503** (Service Unavailable). C'est préférable à un
plantage : le processus reste en vie, journalise la cause (`erreur` dans la réponse),
et la plateforme de la séance 3 voit clairement « conteneur démarré mais pas prêt ».
Elle n'envoie pas de trafic à cette instance et peut alerter, au lieu de relancer en
boucle un conteneur qui plante sans qu'on voie pourquoi.

### Question 4.1
Séance 1 : une seule dépendance (`confluent-kafka`), image de **193 Mo** pour une base
`python:3.12-slim` de 145 Mo, soit environ 48 Mo ajoutés. Séance 2 : cinq dépendances
directes, dont trois bibliothèques scientifiques lourdes (numpy, scipy tirée par
scikit-learn, pandas) avec leurs bibliothèques compilées. Estimation : quelques centaines de
Mo en plus, donc une image autour de 450 à 550 Mo. Mesure : **516 Mo**, soit **+323 Mo
(×2,7)** par rapport à la séance 1. L'écart vient presque entièrement de la couche `pip install`.

## Mesure 13 — image séance 1 vs séance 2
| Relevé | Séance 1 | Séance 2 |
|---|---|---|
| Taille de l'image | 193 Mo | 516 Mo |
| Nombre de couches | 8 non vides | 20 (docker history, couches vides comprises) |
| Construction à froid | non relevée | 49 s |
| Paquets dans pip freeze | non relevé | 19 |

### Question 4.2
Le modèle pèse **9,9 Ko**, l'image **516 Mo** : le modèle représente environ 0,002 % de
l'artefact. Ce qui coûte cher, ce n'est pas ce que le modèle a appris, c'est la pile
logicielle nécessaire pour l'exécuter. Si la taille devenait un problème, il faudrait
optimiser les dépendances en premier : retirer pandas de l'inférence (un tableau numpy
suffit), éviter scipy, ou exporter le pipeline vers un format d'inférence léger (ONNX
Runtime), et partir d'une image de base minimale. Compresser le modèle ne ferait
rien gagner de visible.

## Mesure 15 — cohérence des versions
| Relevé | Valeur |
|---|---|
| scikit-learn du paquet (champ versions) | 1.9.1 |
| scikit-learn épinglé dans requirements.txt | 1.9.1 (+ numpy 2.4.6, pandas 3.0.6, joblib 1.6.0, scipy 1.17.1, Flask 3.1.3, gunicorn 26.2.0) |
| Identiques ? | Oui : pip a installé les mêmes versions que celles de l'entraînement (1.9.1) |
| Message d'erreur exact | Aucune erreur de version. Erreur rencontrée, sans lien avec les versions : `PermissionError: [Errno 13] Permission denied: '/app/app.py'` (fichiers copiés en mode 600, illisibles par `appuser`), corrigée par `RUN chmod -R a+rX /app` |

### Question 4.3
Sans épinglage, l'image aurait cessé de fonctionner à deux moments :
1. **À la prochaine construction sur une machine neuve** (CI, collègue, séance 3) après
   la sortie d'une version incompatible de scikit-learn ou numpy : le modèle ne se
   charge plus, `/health` passe en 503 et l'erreur est visible tout de suite, avant la mise
   en service.
2. **À une reconstruction en production pour une raison sans rapport** (correctif de
   sécurité, modification d'`app.py`) : pip installe alors silencieusement une version
   mineure différente. Le modèle se charge souvent quand même, avec au plus un
   avertissement, mais ses probabilités peuvent changer légèrement et déplacer des cas
   autour du seuil.

Le second est le plus dangereux pour un service déjà en production : rien ne plante, la
sonde reste à 200, et le service rend des décisions différentes de celles qui ont été
évaluées sans que personne ne le remarque.

## Mesure 16 — publication
| Relevé | Valeur |
|---|---|
| Image publiée | acrdermascankorich.azurecr.io/dermascan-api:1.0.0 (linux/amd64) |
| Durée du push | 42 s |
| Digest | sha256:d979c792ceb0652b7aff980ffa2be335a207396032392560150b470316ba8ff0 |
| Dépôts dans le registre | dermascan-api |
| Tags présents | 1.0.0 |

Remarque : le registre n'existait pas (la séance 1 portait sur Kafka). Il a été créé le
2026-10-09 avec `creer_registre.sh`. La policy de l'abonnement Azure for Students n'autorise
que belgiumcentral, denmarkeast, italynorth, polandcentral et spaincentral : France
Central et West Europe ont été refusées (`RequestDisallowedByAzure`).

## Mesure 17 — nettoyage
| Contrôle | Observation |
|---|---|
| Espace libéré par docker system prune | 1,83 Go (plus 3,55 Go libérés en début de séance par `docker system prune -a --volumes`) |
| Espace libéré en séance 1 | non relevé en séance 1 |
| Ressources laissées actives | 1 seule : `acrdermascankorich` (Microsoft.ContainerRegistry/registries, belgiumcentral, Succeeded) dans `rg-dermascan-registre-korich` ; `az group list` ne montre que ce groupe |
| Coût journalier SKU Basic | environ 0,16 € par jour (≈ 5 $ par mois, tarif Azure du SKU Basic, à vérifier sur la page de tarification) |
| Date a_detruire | 2026-12-31 (étiquettes du groupe : `a_detruire=2026-12-31`, `projet=dermascan`) |
| Crédit restant | … (à relever sur microsoftazuresponsorships.com/Balance) |
| Écart avec la séance 1 | … |

### Question 6.1
La séance 1 de ce module portait sur Kafka et n'avait créé aucun registre : il n'existait
donc pas de phrase de ticket à relire. Phrase rédigée aujourd'hui :

> Registre `acrdermascankorich` (ACR Basic, Belgium Central, groupe
> `rg-dermascan-registre-korich`) laissé actif jusqu'au **2026-12-31** : il contient
> l'image `dermascan-api:1.0.0` (digest `sha256:d979c792…`) que les séances 3, 4, 5 et le
> projet fil rouge déploient. Coût : SKU Basic, environ 0,16 € par jour pris sur le crédit
> Azure for Students. À supprimer avec son groupe à cette date.

Nettoyage : un groupe vide hérité du TP1, `rg-dermascan-registre-mk07` (étiquettes
`a_detruire=2027-06-30`, `proprietaire=mkorich`, `role=registre`, aucune ressource), a été
supprimé le 2026-10-09 pour qu'il ne reste qu'un groupe. Le suffixe de séance 1 était donc
`mk07` ; le registre de la séance 2 a été créé avec le suffixe `korich`.

Ce qui l'a fait écrire maintenant : le registre a été créé en séance 2, pas en séance 1, et
la date d'échéance doit couvrir toutes les séances qui en dépendent.
