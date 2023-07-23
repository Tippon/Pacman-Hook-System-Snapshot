#!/bin/sh

TIME=$(date +"%Y-%m-%d_%H-%M")
TIME_SEC=$(date +"%s")

#------Script configuration-------

IS_CONFIGURED=$(cat /etc/core-repo/system-snapshot.conf | grep ^is_configured= | cut -d = -f2-)
IS_ENABLED=$(cat /etc/core-repo/system-snapshot.conf | grep ^is_enabled= | cut -d = -f2-)
OS_NAME=$(cat /etc/core-repo/system-snapshot.conf | grep ^os_name= | cut -d = -f2-)

IS_CONFIGURED=${IS_CONFIGURED:="0"}
IS_ENABLED=${IS_ENABLED:="0"}
OS_NAME=${OS_NAME:="arch"}

#-----Snapshot configuration------

TIME_MIN=$(cat /etc/core-repo/system-snapshot.conf | grep ^minimum_time= | cut -d = -f2-)
MAX_SNAP=$(cat /etc/core-repo/system-snapshot.conf | grep ^maximum_snapshots= | cut -d = -f2-)

TIME_MIN=${TIME_MIN:="3600"}
MAX_SNAP=${MAX_SNAP:="3"}

#-------UUID configuration--------

BTRFS_UUID_SUBVOLUMES=$(cat /etc/core-repo/system-snapshot.conf | grep ^btrfs_uuid_subvolumes= | cut -d = -f2-)
UNCRYPTROOTUUID=$(cat /etc/core-repo/system-snapshot.conf | grep ^unencrypted_root_uuid= | cut -d = -f2)
BOOTABLE_SNAPSHOT=$(cat /etc/core-repo/system-snapshot.conf | grep ^bootable_snapshots= | cut -d = -f2-)

BOOTABLE_SNAPSHOT=${BOOTABLE_SNAPSHOT:="0"}

#----Encryption configuration-----

CRYPTROOTUUID=$(cat /etc/core-repo/system-snapshot.conf | grep ^encrypted_luks_root_uuid= | cut -d = -f2-)
CRYPTROOTNAME=$(cat /etc/core-repo/system-snapshot.conf | grep ^encrypted_luks_root_name= | cut -d = -f2-)
ENCRYPTED=$(cat /etc/core-repo/system-snapshot.conf | grep ^encryption= | cut -d = -f2-)

ENCRYPTED=${ENCRYPTED:="0"}

#---Systemd-boot configuration----

ENABLE_ADDITIONAL_BOOT_PARAMETERS=$(cat /etc/core-repo/system-snapshot.conf | grep ^enable_additional_boot_parameters= | cut -d = -f2-)
ADDITIONAL_BOOT_PARAMETERS=$(cat /etc/core-repo/system-snapshot.conf | grep ^additional_boot_paramaters= | cut -d = -f2-)

#----Create snapshot functions----

#Create a new btrfs snapshot
create_btrfs_snapshot() {
	VOLUME="$1"
	echo ":: System snapshot: Creating new btrfs "$VOLUME" snapshot..."
	btrfs subvolume snapshot /system-snapshot/btrfs/_active/"$VOLUME" /system-snapshot/btrfs/_snapshots/"$VOLUME"_"$TIME"_"$TIME_SEC"
	sleep 1
	echo ":: System snapshot: Btrfs "$VOLUME" snapshot creation complete."
}

#Delete old btrfs snapshots
delete_old_btrfs_snapshots() {
	VOLUME="$1"
	echo ":: System snapshot: Deleting old btrfs "$VOLUME" snapshots..."

	#Get all snapshot timestamps and add them to an array.
	for i in /system-snapshot/btrfs/_snapshots/"$VOLUME"_*; do
		TIME_SNAPSHOT_DELETE=$(echo "$i" | awk -F '_' '{print $NF}')
		DEL_VOL_ARRAY+=($TIME_SNAPSHOT_DELETE)
	done

	#Check array and delete old snapshots except the newest three.
	while [ "${#DEL_VOL_ARRAY[@]}" -gt "$MAX_SNAP" ]; do
		TIME_OLDEST_SNAPSHOT_DELETE=$(printf '%s\n' "${DEL_VOL_ARRAY[@]}" | awk '$1 < m || NR == 1 { m = $1 } END { print m }')
		btrfs subvolume delete /system-snapshot/btrfs/_snapshots/"$VOLUME"_*"$TIME_OLDEST_SNAPSHOT_DELETE"
		sleep 1
		for i in "${!DEL_VOL_ARRAY[@]}"; do
			if [[ "${DEL_VOL_ARRAY[$i]}" == "$TIME_OLDEST_SNAPSHOT_DELETE" ]]; then
				unset DEL_VOL_ARRAY[$i]
			fi
		done
	done

	unset DEL_VOL_ARRAY
	echo ":: System snapshot: Old btrfs "$VOLUME" snapshot deletion complete."
}

#Create a new boot snapshot
create_boot_snapshot() {
	echo ":: System snapshot: Creating new boot snapshot..."

	#Create a new boot snapshot folder and copy the pre-upgraded boot files to it.
	mkdir /system-snapshot/boot/installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}

	for boot_file in /system-snapshot/boot/installs/active/${OS_NAME}/*; do
		echo ":: System snapshot: Copying ${boot_file} to boot snapshot ${OS_NAME}_${TIME}_${TIME_SEC}"
		cp $boot_file /system-snapshot/boot/installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/
	done

	#Create a systemd-boot loader entry for the snapshot.
	if [[ "$ENCRYPTED" == "0" ]]; then
		cat > /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
		title Arch Linux (Snapshot ${TIME})
		linux /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/vmlinuz-linux
		EOC

		if [ -f /system-snapshot/boot/installs/active/${OS_NAME}/amd-ucode.img ]; then
			cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
			initrd /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/amd-ucode.img
			EOC
		elif [ -f /system-snapshot/boot/installs/active/${OS_NAME}/intel-ucode.img ]; then
			cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
			initrd /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/intel-ucode.img
			EOC
		fi

		cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
		initrd /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/initramfs-linux.img
		EOC

		if [[ "$ENABLE_ADDITIONAL_BOOT_PARAMETERS" = "1" ]]; then
				cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
				options root=UUID=${UNCRYPTROOTUUID} rootflags=subvol=_snapshots/root-${OS_NAME}_${TIME}_${TIME_SEC} $ADDITIONAL_BOOT_PARAMETERS rw
				EOC
		elif [[ "$ENABLE_ADDITIONAL_BOOT_PARAMETERS" = "0" ]]; then
				cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
				options root=UUID=${UNCRYPTROOTUUID} rootflags=subvol=_snapshots/root-${OS_NAME}_${TIME}_${TIME_SEC} rw
				EOC
		fi
	else
		cat > /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
		title Arch Linux (Snapshot ${TIME})
		linux /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/vmlinuz-linux
		EOC

		if [ -f /system-snapshot/boot/installs/active/${OS_NAME}/amd-ucode.img ]; then
			cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
			initrd /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/amd-ucode.img
			EOC
		elif [ -f /system-snapshot/boot/installs/active/${OS_NAME}/intel-ucode.img ]; then
			cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
			initrd /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/intel-ucode.img
			EOC
		fi

		cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
		initrd /installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}/initramfs-linux.img
		EOC

		if [[ "$ENABLE_ADDITIONAL_BOOT_PARAMETERS" = "1" ]]; then
				cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
				options luks.name=${CRYPTROOTUUID}=${CRYPTROOTNAME} root=UUID=${UNCRYPTROOTUUID} rootflags=subvol=_snapshots/root-${OS_NAME}_${TIME}_${TIME_SEC} $ADDITIONAL_BOOT_PARAMETERS rw
				EOC
		elif [[ "$ENABLE_ADDITIONAL_BOOT_PARAMETERS" = "0" ]]; then
				cat >> /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_"$TIME"_"$TIME_SEC".conf <<- EOC
				options luks.name=${CRYPTROOTUUID}=${CRYPTROOTNAME} root=UUID=${UNCRYPTROOTUUID} rootflags=subvol=_snapshots/root-${OS_NAME}_${TIME}_${TIME_SEC} rw
				EOC
		fi
	fi

	echo ":: System snapshot: Created boot snapshot /system-snapshot/boot/installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}"
	echo ":: System snapshot: Created systemd-boot entry /system-snapshot/boot/loader/entries/${OS_NAME}-snapshot_${TIME}_${TIME_SEC}.conf"
	echo ":: System snapshot: Boot snapshot creation complete."
}

#Delete old boot snapshots
delete_old_boot_snapshots() {
	echo ":: System snapshot: Deleting old boot snapshots..."
	#Get all boot snapshot timestamps and add them to an array.
	for i in /system-snapshot/boot/installs/snapshots/${OS_NAME}_*; do
		TIME_BOOT_SNAPSHOT_DELETE=$(echo "$i" | awk -F '_' '{print $NF}')
		DEL_BOOT_ARRAY+=($TIME_BOOT_SNAPSHOT_DELETE)
	done

	#Check array and delete old boot snapshots except the newest three.
	while [ "${#DEL_BOOT_ARRAY[@]}" -gt "$MAX_SNAP" ]; do
		TIME_OLDEST_BOOT_DELETE=$(printf '%s\n' "${DEL_BOOT_ARRAY[@]}" | awk '$1 < m || NR == 1 { m = $1 } END { print m }')
		DELETE_SNAP=$(find /system-snapshot/boot/installs/snapshots/ -maxdepth 1 -name "${OS_NAME}_*${TIME_OLDEST_BOOT_DELETE}")
		DELETE_SNAP_ENTRY=$(find /system-snapshot/boot/loader/entries/ -maxdepth 1 -name "${OS_NAME}-snapshot*${TIME_OLDEST_BOOT_DELETE}.conf")
		#rm -rf /system-snapshot/boot/installs/snapshots/${OS_NAME}_*"$TIME_OLDEST_BOOT_DELETE"
		#rm /system-snapshot/boot/loader/entries/${OS_NAME}-zen*"$TIME_OLDEST_BOOT_DELETE".conf
		rm -rf "$DELETE_SNAP"
		rm "$DELETE_SNAP_ENTRY"
		sleep 1
		for i in "${!DEL_BOOT_ARRAY[@]}"; do
			if [[ "${DEL_BOOT_ARRAY[$i]}" == "$TIME_OLDEST_BOOT_DELETE" ]]; then
				unset DEL_BOOT_ARRAY[$i]
			fi
		done
		if [ ! -z "$DELETE_SNAP" ]; then
			echo ":: System snapshot: Deleted boot snapshot ${DELETE_SNAP}"
		fi
		if [ ! -z "$DELETE_SNAP_ENTRY" ]; then
			echo ":: System snapshot: Deleted systemd-boot entry ${DELETE_SNAP_ENTRY}"
		fi
	done
	echo ":: System snapshot: Old boot snapshot deletion complete."
}

#Replace fstab entries for volumes
replace_fstab_entries() {
	VOLUME="$1"
	#Replace the btrfs subvolume names in the snapshot's /etc/fstab.
	echo ":: System snapshot: Changing snapshot fstab for volume ${VOLUME}"
	sed -i "s*subvol=_active/${VOLUME}*subvol=_snapshots/${VOLUME}_${TIME}_${TIME_SEC}*g" /system-snapshot/fstab/_snapshots/root-${OS_NAME}_"$TIME"_"$TIME_SEC"/etc/fstab
	echo ":: System snapshot: Changing of fstab for volume ${VOLUME} complete"
}

#Replace fstab entries for boot
replace_fstab_boot() {
	#Replace the boot and boot bind mount names in /etc/fstab.
	echo ":: System snapshot: Changing snapshot fstab for boot."
	sed -i "s*mnt/backup-boot/installs/active/${OS_NAME}*mnt/backup-boot/installs/snapshots/${OS_NAME}_${TIME}_${TIME_SEC}*g" /system-snapshot/fstab/_snapshots/root-${OS_NAME}_"$TIME"_"$TIME_SEC"/etc/fstab
	echo ":: System snapshot: Changing of fstab for boot complete."
}

#----Restore snapshot functions----

#Delete active btrfs snapshots
delete_active_btrfs_snapshots() {
	VOLUME="$1"
	echo ":: System snapshot restore: Deleting active btrfs "$VOLUME" subvolume..."
	btrfs subvolume delete /system-snapshot/btrfs/_active/${VOLUME}
	sleep 1
	echo ":: System snapshot restore: Active btrfs "$VOLUME" subvolume deletion complete."
}

#Restore btrfs snapshot to active
restore_btrfs_snapshot() {
	VOLUME="$1"
	SELECTED_SNAPSHOT="$2"
	echo ":: System snapshot restore: Restoring btrfs "$VOLUME" snapshot to active..."
	btrfs subvolume snapshot /system-snapshot/btrfs/_snapshots/"$SELECTED_SNAPSHOT" /system-snapshot/btrfs/_active/${VOLUME}
	sleep 1
	echo ":: System snapshot restore: Btrfs "$VOLUME" snapshot restoration complete."
}

#Delete active boot
delete_active_boot_snapshots() {
	echo ":: System snapshot restore: Deleting active boot..."
	rm -rf /system-snapshot/boot/installs/active/${OS_NAME}
	echo ":: System snapshot restore: Active boot deletion complete."
}

#Restore boot snapshot to active
restore_boot_snapshot() {
	SELECTED_SNAPSHOT="$1"
	echo ":: System snapshot restore: Restoring boot snapshot to active..."

	#Create a new active boot folder and copy the snapshot boot files to it.
	mkdir /system-snapshot/boot/installs/active/${OS_NAME}

	for boot_file in /system-snapshot/boot/installs/snapshots/${SELECTED_SNAPSHOT}/*; do
		echo ":: System snapshot restore: Copying ${boot_file} to active boot from snapshot."
		cp $boot_file /system-snapshot/boot/installs/active/${OS_NAME}/
	done

	echo ":: System snapshot restore: Restored active boot from snapshot /system-snapshot/boot/installs/snapshots/${SELECTED_SNAPSHOT}"
	echo ":: System snapshot restore: Active boot restoration complete."
}

#Replace fstab entries for volumes
restore_fstab_entries() {
	VOLUME="$1"
	SELECTED_SNAPSHOT="$2"
	#Replace the btrfs subvolume names in the active's /etc/fstab.
	echo ":: System snapshot restore: Changing active fstab for volume ${VOLUME}"
	sed -i "s*subvol=_snapshots/${SELECTED_SNAPSHOT}*subvol=_active/${VOLUME}*g" /system-snapshot/fstab/_active/root-${OS_NAME}/etc/fstab
	echo ":: System snapshot restore: Changing of fstab for volume ${VOLUME} complete"
}

#Replace fstab entries for boot
restore_fstab_boot() {
	#Replace the boot and boot bind mount names in /etc/fstab.
	SELECTED_SNAPSHOT="$1"
	echo ":: System snapshot restore: Changing active fstab for boot."
	sed -i "s*mnt/backup-boot/installs/snapshots/${SELECTED_SNAPSHOT}*mnt/backup-boot/installs/active/${OS_NAME}*g" /system-snapshot/fstab/_active/root-${OS_NAME}/etc/fstab
	echo ":: System snapshot restore: Changing of fstab for boot complete."
}

#Uninstall systemd-boot, create the system-snapshot folder structure, remount the boot partition and reinstall systemd-boot
install_system_snapshot() {
	BOOT_PART=$(mount | grep boot | awk '{print $1}')
	BOOT_UUID=$(blkid -s UUID -o value $BOOT_PART)
	IS_INSTALLED=$(cat /etc/core-repo/system-snapshot.conf | grep ^is_installed= | cut -d = -f2-)

	if [[ "$IS_INSTALLED" == "0" ]]; then
		mkdir -p /system-snapshot/{btrfs,boot,fstab,bckp}
		cp -rf /boot/* /system-snapshot/bckp
		bootctl --path=/boot remove
		rm -rf /boot/*
		umount /boot
		mount --uuid ${BOOT_UUID} /system-snapshot/boot
		mkdir -p /system-snapshot/boot/installs/active/arch
		mkdir -p /system-snapshot/boot/installs/snapshots
		bootctl --path=/system-snapshot/boot install
		rm /system-snapshot/boot/loader/loader.conf
		mv /system-snapshot/bckp/loader/entries/* /system-snapshot/boot/loader/entries/
		for boot_file in /system-snapshot/boot/loader/entries/*; do
			sed -i "s*initrd /amd-ucode.img*initrd /installs/active/arch/amd-ucode.img*g" $boot_file
			sed -i "s*initrd /intel-ucode.img*initrd /installs/active/arch/intel-ucode.img*g" $boot_file
			sed -i "s*linux /vmlinuz-linux*linux /installs/active/arch/vmlinuz-linux*g" $boot_file
			sed -i "s*linux /vmlinuz-linux-lts*linux /installs/active/arch/vmlinuz-linux-lts*g" $boot_file
			sed -i "s*initrd /initramfs-linux.img*initrd /installs/active/arch/initramfs-linux.img*g" $boot_file
			sed -i "s*initrd /initramfs-linux-fallback.img*initrd /installs/active/arch/initramfs-linux-fallback.img*g" $boot_file
			sed -i "s*initrd /initramfs-linux-lts.img*initrd /installs/active/arch/initramfs-linux-lts.img*g" $boot_file
			sed -i "s*initrd /initramfs-linux-lts-fallback.img*initrd /installs/active/arch/initramfs-linux-lts-fallback.img*g" $boot_file
		done
		mount --bind /system-snapshot/boot/installs/active/arch /boot
		mv /system-snapshot/bckp/*.img /system-snapshot/boot/installs/active/arch/
		mv /system-snapshot/bckp/vmlinuz* /system-snapshot/boot/installs/active/arch/
		mv /system-snapshot/bckp/*-ucode.img /system-snapshot/boot/installs/active/arch/
		sed -i "s*/boot*/system-snapshot/boot*g" /etc/fstab
		sed -i "\*/system-snapshot/boot*a /system-snapshot/boot/installs/active/arch              /boot           none            defaults,bind   0 0" /etc/fstab
		rm -rf /system-snapshot/bckp
		sed -i "s*is_installed=0*is_installed=1*" /etc/core-repo/system-snapshot.conf
	else
		echo ":: System snapshot restore: Already installed. Aborted."
	fi
}

#----Main functions----

create_snapshots() {

	create_snapshot_function() {
		ACTIVE_VOLUME_FUNCTION="$1"
		create_btrfs_snapshot $ACTIVE_VOLUME_FUNCTION
		delete_old_btrfs_snapshots $ACTIVE_VOLUME_FUNCTION
		if [[ "$BOOTABLE_SNAPSHOT" == "1" ]]; then
			replace_fstab_entries $ACTIVE_VOLUME_FUNCTION
			if [[ "$ACTIVE_VOLUME_FUNCTION" = "root-${OS_NAME}" ]]; then
				create_boot_snapshot
				delete_old_boot_snapshots
				replace_fstab_boot
			fi
		fi
	}

	ADDITIONAL_ARGUMENT="$1"
	if [[ "$IS_CONFIGURED" = "1" ]]; then
		if [[ "$IS_ENABLED" == "1" && "$ADDITIONAL_ARGUMENT" == "hook" ]] || [[ "$ADDITIONAL_ARGUMENT" != "hook" ]]; then
			echo ":: System snapshot: Beginning system snapshot generation."

			if [[ ! -d /system-snapshot/btrfs ]]; then
				mkdir -p /system-snapshot/btrfs
			fi

			if [[ ! -d /system-snapshot/fstab ]]; then
				mkdir -p /system-snapshot/fstab
			fi

			mount --uuid ${UNCRYPTROOTUUID} /system-snapshot/fstab

			IFS=" "
			for UUID_VOLUME_ARRAY in $BTRFS_UUID_SUBVOLUMES; do
				BTRFS_UUID=$(echo "${UUID_VOLUME_ARRAY}" | awk -F ':' '{print $1}')
				BTRFS_SUBVOLUMES=$(echo "${UUID_VOLUME_ARRAY}" | awk -F ':' '{print $2}')

				mount --uuid "${BTRFS_UUID}" /system-snapshot/btrfs

				IFS=","
				for ACTIVE_VOLUME in ${BTRFS_SUBVOLUMES}; do
					#Check the timestamp of the last snapshot generated. If it's withing the threshold, no new snapshots will be generated and the script will exit.
					echo ":: System snapshot: Checking time of last btrfs "$ACTIVE_VOLUME" snapshot generated..."
					if ls /system-snapshot/btrfs/_snapshots/"$ACTIVE_VOLUME"_* &> /dev/null; then
						for i in /system-snapshot/btrfs/_snapshots/"$ACTIVE_VOLUME"_*; do
							TIME_SNAPSHOT_CHECK=$(echo "$i" | awk -F '_' '{print $NF}')
							TIME_DIFFRENCE=$(($(date +"%s")-$TIME_SNAPSHOT_CHECK))
							TIME_VOL_ARRAY+=($TIME_DIFFRENCE)
						done

						TIME_OLDEST_SNAPSHOT=$(printf '%s\n' "${TIME_VOL_ARRAY[@]}" | awk '$1 < m || NR == 1 { m = $1 } END { print m }')

						if [[ "$ADDITIONAL_ARGUMENT" == "force" ]]; then
							create_snapshot_function $ACTIVE_VOLUME
						else
							if [ "$TIME_OLDEST_SNAPSHOT" -le "$TIME_MIN" ]; then
								echo ":: System snapshot: Pre-upgrade btrfs "$ACTIVE_VOLUME" snapshot canceled. Time threshold not met."
							else
								create_snapshot_function $ACTIVE_VOLUME
							fi
						fi
						unset TIME_VOL_ARRAY
					else
						create_btrfs_snapshot $ACTIVE_VOLUME
						if [[ "$BOOTABLE_SNAPSHOT" == "1" ]]; then
							replace_fstab_entries $ACTIVE_VOLUME
							if [[ "$ACTIVE_VOLUME" == "root-${OS_NAME}" ]]; then
								create_boot_snapshot
								replace_fstab_boot
							fi
						fi
					fi
				done

				umount -R /system-snapshot/btrfs
			done
			umount -R /system-snapshot/fstab

			echo ":: System snapshot: Complete."
		elif [[ "$IS_ENABLED" == "0" && "$ADDITIONAL_ARGUMENT" == "hook" ]]; then
			echo ":: System snapshot: Disabled."
		fi
	else
		echo ":: System snapshot: Not configured. Aborted."
	fi
}

restore_snapshots() {
#Generate selection menu for snapshots and restore the selected snapshot
	if [[ "$IS_CONFIGURED" == "1" ]]; then
		echo ":: System snapshot restore: Beginning system snapshot restoration."

		if [[ ! -d /system-snapshot/btrfs ]]; then
			mkdir -p /system-snapshot/btrfs
		fi

		if [[ ! -d /system-snapshot/fstab ]]; then
			mkdir -p /system-snapshot/fstab
		fi

		mount --uuid ${UNCRYPTROOTUUID} /system-snapshot/fstab

		SNAPSHOTS="$(ls -A /system-snapshot/fstab/_snapshots/ | grep root | sed -e 's/^root-//')"

		echo ":: System snapshot restore: Checking if any snapshots present on system..."
		if ls /system-snapshot/fstab/_snapshots/"$ACTIVE_VOLUME"_* &> /dev/null; then
			echo ":: System snapshot restore: No snapshots present on system. Aborting..."
		else
			echo ":: System snapshot restore: Please select a snapshot from the list or use ctrl+c to cancel."
			select SELECT_SNAPSHOT in ${SNAPSHOTS}; do
				echo ":: System snapshot restore: Snapshot selected. Starting restoration..."

				IFS=" "
				for UUID_VOLUME_ARRAY in $BTRFS_UUID_SUBVOLUMES; do
					BTRFS_UUID=$(echo "${UUID_VOLUME_ARRAY}" | awk -F ':' '{print $1}')
					BTRFS_SUBVOLUMES=$(echo "${UUID_VOLUME_ARRAY}" | awk -F ':' '{print $2}')

					mount --uuid "${BTRFS_UUID}" /system-snapshot/btrfs

					IFS=","
					for ACTIVE_VOLUME in ${BTRFS_SUBVOLUMES}; do
						delete_active_btrfs_snapshots $ACTIVE_VOLUME
						restore_btrfs_snapshot $ACTIVE_VOLUME $ACTIVE_VOLUME$(echo "$SELECT_SNAPSHOT" | sed -e "s/^${OS_NAME}//")
						if [[ "$BOOTABLE_SNAPSHOT" == "1" ]]; then
							restore_fstab_entries $ACTIVE_VOLUME $ACTIVE_VOLUME$(echo "$SELECT_SNAPSHOT" | sed -e "s/^${OS_NAME}//")
							if [[ "$ACTIVE_VOLUME" == "root-${OS_NAME}" ]]; then
								delete_active_boot_snapshots
								restore_boot_snapshot $SELECT_SNAPSHOT
								restore_fstab_boot $ACTIVE_VOLUME$(echo "$SELECT_SNAPSHOT" | sed -e "s/^${OS_NAME}//")
							fi
						fi
					done
					umount -R /system-snapshot/btrfs
				done
				umount -R /system-snapshot/fstab
				echo ":: System snapshot restore: Complete."
				exit 0
			done
		fi
	else
		echo ":: System snapshot restore: Not configured. Aborted."
	fi
}

enable_system_snapshots() {
	if [[ "$IS_ENABLED" = "0" ]]; then
		sed -i "s*is_enabled=0*is_enabled=1*" /etc/core-repo/system-snapshot.conf
		echo ":: System snapshot: Enabled."
	else
		echo ":: System snapshot: Already enabled."
	fi
}

disable_system_snapshots() {
	if [[ "$IS_ENABLED" = "1" ]]; then
		sed -i "s*is_enabled=1*is_enabled=0*" /etc/core-repo/system-snapshot.conf
		echo ":: System snapshot: Disabled."
	else
		echo ":: System snapshot: Already disabled."
	fi
}

help_info() {
	echo -e "${CYAN}Time: $(date +"%Y-%m-%d %H:%M:%S") ${NC}"
	echo -e "${CYAN}System snapshot script by 7thCore${NC}"
	echo "Version: $VERSION"
	echo ""
	echo -e "${GREEN}create  ${RED}- ${GREEN}Creates a new system snapshot if configured time threshold is met. Use <create force> to ignore time threshold${NC}"
	echo -e "${GREEN}restore ${RED}- ${GREEN}Restores system snapshot. Use only when booted in to a snapshot or chroot-ed in the system${NC}"
	echo -e "${GREEN}install ${RED}- ${GREEN}Installs the script's folder structure and reinstalls systemd-boot${NC}"
	echo -e "${GREEN}enable  ${RED}- ${GREEN}Enables automatic system snapshot generation when updating via pacman${NC}"
	echo -e "${GREEN}disable ${RED}- ${GREEN}Disables automatic system snapshot generation when updating via pacman${NC}"
	echo ""
	echo -e "${LIGHTRED}Example usage: ./$SCRIPT_NAME create${NC}"
	echo ""
	echo -e "${CYAN}Have a nice day!${NC}"
	echo ""
}

case "$1" in
	-help)
		help_info
		;;
	create)
		create_snapshots "$2"
		;;
	restore)
		restore_snapshots
		;;
	install)
		install_system_snapshot
		;;
	enable)
		enable_system_snapshots
		;;
	disable)
		disable_system_snapshots
		;;
	*)
	help_info
	;;
esac
