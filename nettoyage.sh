#!/usr/bin/env bash
# Nettoyage de fin de seance (mesure 17) : bash ~/s2-dermascan/nettoyage.sh
cd "$(dirname "$0")"; mkdir -p captures
export PATH="$HOME/.azcli/bin:$PATH"
RG=rg-dermascan-registre-korich
{
echo "== Docker : conteneur de la seance, puis images locales non utilisees"
docker rm -f dermascan-api 2>/dev/null
docker system prune -f
echo; echo "== Ressources laissees actives dans $RG"
az resource list --resource-group "$RG" --output table
echo; echo "== Etiquettes du groupe"
az group show --name "$RG" --query "tags" --output json
echo; echo "== Tous les groupes de l'abonnement (doit n'en montrer qu'un)"
az group list --output table
echo; echo "== Image publiee"
az acr repository show-tags --name acrdermascankorich --repository dermascan-api -o table
} 2>&1 | tee captures/nettoyage.txt
echo; echo "Reste a faire a la main : relever le credit restant sur https://www.microsoftazuresponsorships.com/Balance"
