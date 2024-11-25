#!/bin/bash

# Variables
DISKS=(sdb sdc sdd sde)
PARTITIONS=()
MOUNT_POINTS=(/mnt/disk1 /mnt/disk2 /mnt/disk3 /mnt/disk4)
MINIO_USER="minio-user"
CERT_DIR="/home/${MINIO_USER}/.minio/certs"

# Function to log errors
log_error() {
  echo "[ERROR] $1"
  exit 1
}

# Install xfsprogs and other required tools
echo "Installing required packages..."
sudo apt-get update && sudo apt-get install -y xfsprogs parted || log_error "Failed to install required packages."

# Create Partitions
echo "Creating partitions on disks..."
for disk in "${DISKS[@]}"; do
  if sudo parted -s /dev/$disk print | grep -q "Partition Table: gpt"; then
    echo "Partition table already exists on /dev/$disk."
  else
    sudo parted -s /dev/$disk mklabel gpt || log_error "Failed to create GPT partition table on /dev/$disk."
  fi

  if sudo parted -s /dev/$disk print | grep -q "^ 1"; then
    echo "Partition already exists on /dev/$disk."
  else
    sudo parted -s /dev/$disk mkpart primary 0% 100% || log_error "Failed to create partition on /dev/$disk."
  fi
  PARTITIONS+=("/dev/${disk}1")
done

# Prepare Physical Volumes and Volume Groups
echo "Creating Physical Volumes and Volume Groups..."
for i in "${!PARTITIONS[@]}"; do
  if sudo pvs | grep -q "${PARTITIONS[$i]}"; then
    echo "Physical volume already exists for ${PARTITIONS[$i]}."
  else
    sudo pvcreate ${PARTITIONS[$i]} || log_error "Failed to create physical volume for ${PARTITIONS[$i]}."
  fi

  if sudo vgs | grep -q "minio-disk$((i + 1))"; then
    echo "Volume group minio-disk$((i + 1)) already exists."
  else
    sudo vgcreate minio-disk$((i + 1)) ${PARTITIONS[$i]} || log_error "Failed to create volume group minio-disk$((i + 1))."
  fi
done

# Create Logical Volumes
echo "Creating Logical Volumes..."
for i in $(seq 1 ${#PARTITIONS[@]}); do
  if sudo lvs | grep -q "minio-disk$i"; then
    echo "Logical volume lv already exists for minio-disk$i."
  else
    sudo lvcreate -n lv -l 100%FREE minio-disk$i || log_error "Failed to create logical volume for minio-disk$i."
  fi
done

# Create and Format Mount Points
echo "Creating and Formatting Mount Points..."
for i in "${!MOUNT_POINTS[@]}"; do
  if [ -d "${MOUNT_POINTS[$i]}" ]; then
    echo "Mount point ${MOUNT_POINTS[$i]} already exists."
  else
    sudo mkdir -p ${MOUNT_POINTS[$i]} || log_error "Failed to create mount point ${MOUNT_POINTS[$i]}."
  fi

  if mount | grep -q "${MOUNT_POINTS[$i]}"; then
    echo "Volume already mounted on ${MOUNT_POINTS[$i]}."
  else
    sudo mkfs.xfs /dev/mapper/minio--disk$((i + 1))-lv || log_error "Failed to format volume for minio--disk$((i + 1))."
    echo "/dev/mapper/minio--disk$((i + 1))-lv ${MOUNT_POINTS[$i]} xfs defaults 0 0" | sudo tee -a /etc/fstab
    sudo mount ${MOUNT_POINTS[$i]} || log_error "Failed to mount ${MOUNT_POINTS[$i]}."
  fi
done

# Reload System Daemon
echo "Reloading System Daemon..."
sudo systemctl daemon-reload || log_error "Failed to reload system daemon."

# Create MinIO User and Group
echo "Creating MinIO User and Group..."
if id -u ${MINIO_USER} &>/dev/null; then
  echo "User ${MINIO_USER} already exists."
else
  sudo groupadd -r ${MINIO_USER} || log_error "Failed to create group ${MINIO_USER}."
  sudo useradd -M -r -g ${MINIO_USER} ${MINIO_USER} || log_error "Failed to create user ${MINIO_USER}."
fi

# Set Ownership on Mount Points
echo "Setting Ownership on Mount Points..."
for mount in "${MOUNT_POINTS[@]}"; do
  sudo chown -R ${MINIO_USER}:${MINIO_USER} $mount || log_error "Failed to set ownership for $mount."
done

# Prepare Certificate Directories
echo "Preparing Certificate Directories..."
if [ -d "${CERT_DIR}" ]; then
  echo "Certificate directory ${CERT_DIR} already exists."
else
  sudo mkdir -p ${CERT_DIR}/CAs || log_error "Failed to create certificate directories."
  sudo chown -R ${MINIO_USER}:${MINIO_USER} ${CERT_DIR} || log_error "Failed to set ownership for ${CERT_DIR}."
  sudo chmod -R 700 ${CERT_DIR} || log_error "Failed to set permissions for ${CERT_DIR}."
fi

# Configure /etc/hosts
echo "Configuring /etc/hosts..."
HOST_ENTRIES="192.168.56.6 minio1.local
192.168.56.4 minio2.local
192.168.56.3 minio3.local
192.168.56.7 minio4.local"

if ! grep -Fxq "$HOST_ENTRIES" /etc/hosts; then
  echo "$HOST_ENTRIES" | sudo tee -a /etc/hosts || log_error "Failed to update /etc/hosts."
else
  echo "/etc/hosts is already configured."
fi

echo "Script completed successfully!"

