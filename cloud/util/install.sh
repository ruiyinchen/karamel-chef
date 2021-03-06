#!/bin/bash

help()
{
    echo ""
    echo "Usage: $0 cpu|gpu|cluster [skip-create] [community|kubernetes]"
    echo "Create a VM or a cluster and install Hopsworks on it."
    echo ""    
    exit 1
}

if [ $# -lt 1 ] ; then
    help
fi


error_download_url()
{
    echo ""
    echo "Error. You need to export the following environment variable to run this script:"
    echo "export ENTERPRISE_DOWNLOAD_URL=https://path/to/hopsworks/enterprise/binaries"
    echo ""    
    exit
}

check_download_url()
{
    if [ "$ENTERPRISE_DOWNLOAD_URL" == "" ] ; then
	echo ""
	echo "Error. You need to set the environment variable \$ENTERPRISE_DOWNLOAD_URL to the URL for the enterprise binaries."
	echo ""
	echo "You can re-run this command with the 'community' switch to install community Hopsworks. For example: "
	echo "./install.sh gpu community"
	echo "or"
	echo "./install.sh cpu community"	
	echo ""	
	exit 3
    fi
    if [ "$ENTERPRISE_USER" == "" ] ; then    
        echo ""
        printf "Enter the username for downloading the Enterprise binaries: "
        read ENTERPRISE_USER
        if [ "$ENTERPRISE_USER" == "" ] ; then
	    echo "Enterprise username cannot be empty"
	    echo "Exiting."
	    exit 3
	fi
    fi
    if [ "$ENTERPRISE_PASSWORD" == "" ] ; then    
        echo ""
        printf "Enter the password for the user ($ENTERPRISE_USER): "
        read -s ENTERPRISE_PASSWORD
	echo ""
        if [ "$ENTERPRISE_PASSWORD" == "" ] ; then
	    echo "The password cannot be empty"
	    echo "Exiting."
	    exit 3
	fi
    fi
}


get_ips()
{
    IP=$(./_list_public.sh cluster)
    PRIVATE_IP=$(./_list_private.sh cluster)    
    echo -e "Head node.\t Public IP: $IP \t Private IP: $PRIVATE_IP"

    CPU=$(./_list_public.sh cpu)
    PRIVATE_CPU=$(./_list_private.sh cpu)
    echo -e "Cpu node.\t Public IP: $CPU \t Private IP: $PRIVATE_CPU"


    GPU=$(./_list_public.sh gpu)
    PRIVATE_GPU=$(./_list_private.sh gpu)
    echo -e "Gpu node.\t Public IP: $GPU \t Private IP: $PRIVATE_GPU"
}    

clear_known_hosts()
{
   echo "   ssh-keygen -R $host_ip -f /home/$USER/.ssh/known_host"
   ssh-keygen -R $host_ip -f /home/$USER/.ssh/known_hosts 
}    

###################################################################
#   MAIN                                                          #
###################################################################

if [ "$1" != "cpu" ] && [ "$1" != "gpu" ] && [ "$1" != "cluster" ] ; then
    help
    exit 3
fi

host_ip=
. config.sh $1

get_ips

if [ "$2" == "community" ] || [ "$3" == "community" ] ; then
    HOPSWORKS_VERSION=cluster
elif [ "$2" == "kubernetes" ] || [ "$3" == "kubernetes" ] ; then
    HOPSWORKS_VERSION=kubernetes
    check_download_url
    if [[ ! $BRANCH =~ "-kube" ]] ; then
      echo "Found branch: $BRANCH"
      # check if this is a version branch, if yes update to the kube version of the branch.
      branch_regex='^[1-9]+\.[1-9]+'
      #      if [[ $BRANCH =~ $branch_regex ]] || [[ "$BRANCH" == "master" ]] ; then
      if [[ $BRANCH =~ $branch_regex ]] ; then      
	cp -f ../../hopsworks-installer.sh .hopsworks-installer.sh
        escaped=${BRANCH//./\\.}
#        perl -pi -e "s/HOPSWORKS_BRANCH=$escaped/HOPSWORKS_BRANCH=${escaped}-kube/" .hopsworks-installer.sh
#        BRANCH=${BRANCH}-kube       
      else
	echo "WARNING: your hopsworks-chef branch, defined in hopsworks-installer.sh, does not appear to be a kubernetes branch: "
	echo "$BRANCH"
	echo "If you are developing a kubernetes branch for hopsworks-chef, please rename it to: XXX-kube to skip this warning."
	echo ""
        printf 'Do you want to install this branch anyway? (y/n (default y):'
        read ACCEPT
        if [ "$ACCEPT" == "y" ] || [ "$ACCEPT" == "yes" ] || [ "$ACCEPT" == "" ] ; then
	    echo "Ok!"
            cp -f ../../hopsworks-installer.sh .hopsworks-installer.sh	    
	else
	    exit 3
	fi
      fi
      echo "Installing branch: $BRANCH"
    else
      cp -f ../../hopsworks-installer.sh .hopsworks-installer.sh
    fi
else
    HOPSWORKS_VERSION=enterprise
    check_download_url
fi

if [ ! "$2" == "skip-create" ] ; then
    IP=$(./_list_public.sh $1)    
    if [ "$IP" != "" ] ; then
	echo "VM already created and running at: $IP"
	echo "Exiting..."
	exit 3
    fi
    echo ""
    echo "Creating VM(s) ...."
    echo ""    
    ./_create.sh $1
    if [ $? -ne 0 ] ; then
	echo ""	
	echo "Problem creating a VM. Exiting....."
	echo ""
        exit 12
    fi
else
    echo "Skipping VM creation...."
fi	

get_ips

IP=$(./_list_public.sh $1)
echo "IP: $IP for $NAME"

host_ip=$IP
clear_known_hosts

if [[ "$IMAGE" == *"centos"* ]] ; then
    echo "ssh -t -o StrictHostKeyChecking=no $IP \"sudo yum install wget -y > /dev/null\""
    ssh -t -o StrictHostKeyChecking=no $IP "sudo yum install wget -y > /dev/null"
fi    


echo "Installing installer on $IP"
#ssh -t -o StrictHostKeyChecking=no $IP "wget -nc ${CLUSTER_DEFINITION_BRANCH}/hopsworks-installer.sh && chmod +x hopsworks-installer.sh"
if [ "$2" == "kubernetes" ] || [ "$3" == "kubernetes" ] ; then
    scp -o StrictHostKeyChecking=no .hopsworks-installer.sh ${IP}:~/hopsworks-installer.sh
    rm .hopsworks-installer.sh
else 
    scp -o StrictHostKeyChecking=no ../../hopsworks-installer.sh ${IP}:
fi    
ssh -t -o StrictHostKeyChecking=no $IP "chmod +x hopsworks-installer.sh; mkdir -p cluster-defns"
scp -o StrictHostKeyChecking=no ../../cluster-defns/hopsworks-installer.yml ${IP}:~/cluster-defns/
scp -o StrictHostKeyChecking=no ../../cluster-defns/hopsworks-worker.yml ${IP}:~/cluster-defns/
scp -o StrictHostKeyChecking=no ../../cluster-defns/hopsworks-worker-gpu.yml ${IP}:~/cluster-defns/

if [ $? -ne 0 ] ; then
    echo "Problem installing installer. Exiting..."
    exit 1
fi    


if [ "$1" == "cluster" ] ; then
    ssh -t -o StrictHostKeyChecking=no $IP "if [ ! -e ~/.ssh/id_rsa.pub ] ; then cat /dev/zero | ssh-keygen -q -N \"\" ; fi"
    pubkey=$(ssh -t -o StrictHostKeyChecking=no $IP "cat ~/.ssh/id_rsa.pub")

    keyfile=".pubkey.pub"
    echo "$pubkey" > $keyfile
    echo ""
    echo "Public key for head node is:"
    echo "$pubkey"
    echo ""

    host_ip=$CPU
    clear_known_hosts
    host_ip=$GPU
    clear_known_hosts
    
    WORKERS="-w ${PRIVATE_CPU},${PRIVATE_GPU}"

    ssh-copy-id -o StrictHostKeyChecking=no -f -i $keyfile $CPU
    ssh -t -o StrictHostKeyChecking=no $IP "ssh -t -o StrictHostKeyChecking=no $PRIVATE_CPU \"pwd\""
    if [ $? -ne 0 ] ; then
	echo ""
	echo "Error. Public key SSH from $IP to $PRIVATE_CPU not working."
	echo "Exiting..."
	echo ""
	exit 9
    else
	echo "Success: SSH from $IP to $CPU_PRIVATE"
    fi

    ssh-copy-id -o StrictHostKeyChecking=no -f -i $keyfile $GPU
    ssh -t -o StrictHostKeyChecking=no $IP "ssh -t -o StrictHostKeyChecking=no $PRIVATE_GPU \"pwd\""
    if [ $? -ne 0 ] ; then
	echo ""
	echo "Error. Public key SSH from $IP to $PRIVATE_GPU not working."
	echo "Exiting..."
	echo ""
	exit 10
    else
	echo "Success: SSH from $IP to $GPU_PRIVATE"
    fi

else
    WORKERS="-w none"
fi    

DOWNLOAD=""
if [ "$ENTERPRISE_DOWNLOAD_URL" != "" ] ; then
  DOWNLOAD="-d $ENTERPRISE_DOWNLOAD_URL "
fi
if [ "$ENTERPRISE_USER" != "" ] ; then
  DOWNLOAD_USERNAME="-du $ENTERPRISE_USER "
fi
if [ "$ENTERPRISE_PASSWORD" != "" ] ; then
  DOWNLOAD_PASSWORD="-dp $ENTERPRISE_PASSWORD "
fi
echo
echo "ssh -t -o StrictHostKeyChecking=no $IP "/home/$USER/hopsworks-installer.sh -i $HOPSWORKS_VERSION -ni -c $CLOUD $DOWNLOAD $DOWNLOAD_USERNAME $DOWNLOAD_PASSWORD $WORKERS && sleep 5""
ssh -t -o StrictHostKeyChecking=no $IP "/home/$USER/hopsworks-installer.sh -i $HOPSWORKS_VERSION -ni -c $CLOUD ${DOWNLOAD}${DOWNLOAD_USERNAME}${DOWNLOAD_PASSWORD}$WORKERS && sleep 5"

if [ $? -ne 0 ] ; then
    echo "Problem running installer. Exiting..."
    exit 2
fi

echo ""
echo "****************************************"
echo "*                                      *"
echo "* Public IP access to Hopsworks at:    *"
echo "*   https://${IP}/hopsworks    *"
echo "*                                      *"
echo "* View installation progress:          *"
echo " ssh ${IP} \"tail -f installation.log\"   "
echo "****************************************"

