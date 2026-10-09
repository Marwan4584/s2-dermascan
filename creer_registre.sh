#!/usr/bin/env bash
# Cree le groupe de ressources et le registre ACR (SKU Basic) du module.
# Usage : bash creer_registre.sh   (suffixe et date modifiables ci-dessous)
export PATH="$HOME/.azcli/bin:$PATH"
cd "$(dirname "$0")"; mkdir -p captures
SUFFIXE=korich
RG="rg-dermascan-registre-$SUFFIXE"
ACR_NAME="acrdermascan$SUFFIXE"
A_DETRUIRE=2026-12-31          # fin du module : a ajuster si besoin
# Si le groupe existe deja (essai precedent), on le garde ; sinon on le cree.
if [ "$(az group show --name "$RG" --query properties.provisioningState -o tsv 2>/dev/null)" = "Deleting" ]; then
  echo ">> Le groupe est en cours de suppression (essai precedent) : attente..."
  az group wait --name "$RG" --deleted --timeout 600
fi
az group show --name "$RG" -o table 2>/dev/null || az group create --name "$RG" --location francecentral \
   --tags a_detruire=$A_DETRUIRE projet=dermascan -o table || { echo "ECHEC : creation du groupe."; exit 1; }
# L'abonnement etudiant n'autorise que certaines regions (policy Azure) : on les lit.
REGIONS=$(az policy assignment list --query "[].parameters.listOfAllowedLocations.value[]" -o tsv 2>/dev/null | sort -u)
echo ">> Regions autorisees par la policy : ${REGIONS:-inconnues}" | tee captures/regions_autorisees.txt
[ -n "$REGIONS" ] || REGIONS="francecentral westeurope northeurope swedencentral germanywestcentral polandcentral italynorth spaincentral uksouth"
for REGION in $REGIONS; do
  echo ">> Creation du registre dans la region $REGION"
  if az acr create --resource-group "$RG" --name "$ACR_NAME" --sku Basic \
       --location "$REGION" --tags a_detruire=$A_DETRUIRE -o table; then
    echo "SUFFIXE=$SUFFIXE RG=$RG ACR_NAME=$ACR_NAME REGION=$REGION A_DETRUIRE=$A_DETRUIRE" | tee captures/registre.txt
    az acr show --name "$ACR_NAME" --query loginServer -o tsv | tee -a captures/registre.txt
    exit 0
  fi
done
echo "ECHEC : creation du registre impossible (voir les messages ci-dessus)."; exit 1
