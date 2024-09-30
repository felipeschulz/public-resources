#!/bin/sh
ClusterRGName="rg-XXX"
VNetRGName="VNet-RG-XXX"
Location="eastus2"
VNetName="vnet-XXX"
SubnetClusterName="snet-aks"
DNSPrivateDNSName="privatelink.$Location.azmk8s.io"
ClusterName="aks-private-XXX"
SubscriptionID="XXXXXX"
ManagedIdentityName="mi-$ClusterName"
VNetID=$(az network vnet show --name $VNetName --resource-group $VNetRGName --query 'id' -o tsv)
SubnetID=$VNetID/subnets/$SubnetClusterName

#Create a Private DNS Zone
az network private-dns zone create \
--resource-group $ClusterRGName \
--name $DNSPrivateDNSName 

DNSPrivateZoneID=$(az network private-dns zone show --resource-group $ClusterRGName --name $DNSPrivateDNSName --query 'id' -o tsv)

#Create a VNet Link with Private DNS Zone
az network private-dns link vnet create \
--resource-group $ClusterRGName \
--name VNetLink$VNetName \
--zone-name $DNSPrivateDNSName \
--virtual-network $VNetID \
--registration-enable false 

#Create a Managed Identity to Cluster
az identity create \
--name $ManagedIdentityName \
--resource-group $ClusterRGName
echo "Waiting Managed Identity creation" && sleep 15s
ManagedIdentityID=$(az identity show --name $ManagedIdentityName --resource-group $ClusterRGName --query 'clientId' -o tsv)

#Assign roles on Managed Identity
az role assignment create --role "Private DNS Zone Contributor" --assignee $ManagedIdentityID --scope $DNSPrivateZoneID
az role assignment create --role "Network Contributor" --assignee $ManagedIdentityID --scope $VNetID

echo "Waiting AAD Role propagation" && sleep 15s && echo "Starting Cluster Deploy"

AssignIdentityID=$(az identity show --name $ManagedIdentityName --resource-group $ClusterRGName --query 'id' -o tsv)

#Create Private Cluster
az aks create \
--location "East US 2" \
--subscription $SubscriptionID \
--resource-group $ClusterRGName \
--name $ClusterName \
--vm-set-type VirtualMachineScaleSets \
--enable-cluster-autoscaler \
--min-count 1 \
--max-count 3 \
--load-balancer-sku Standard \
--generate-ssh-keys \
--service-cidr 10.0.0.0/16 \
--dns-service-ip 10.0.0.10 \
--vnet-subnet-id $SubnetID \
--network-plugin azure \
--node-vm-size Standard_B2s \
--kubernetes-version 1.29.0 \
--outbound-type loadBalancer \
--network-policy calico \
--enable-addons azure-policy \
--enable-private-cluster \
--enable-managed-identity \
--enable-azure-rbac \
--enable-aad \
--disable-public-fqdn \
--assign-identity $AssignIdentityID \
--private-dns-zone $DNSPrivateZoneID

