#!/bin/sh -
# $Id$
#
# Create a chroot jail for rcynic.
#
# This is approximately what a package installation script might do.

: ${jaildir="${DESTDIR}/var/rcynic"}
: ${jailuser="rcynic"}
: ${jailgroup="rcynic"}
: ${setupcron="NO"}

echo "Setting up \"${jaildir}\" as a chroot jail for rcynic."

if ${AWK} -F: -v jailgroup="${jailgroup}" 'BEGIN {status = 1} $1 == jailgroup {status = 0} END {exit status}' /etc/group
then
    echo "You already have a group \"${jailgroup}\", so I will use it."
elif /usr/sbin/groupadd ${jailgroup}
then
    echo "Added group \"${jailgroup}\"."
else
    echo "Adding group \"${jailgroup}\" failed..."
    echo "Please create it, then try again."
    exit 1
fi

# The adduser program on CentOS 5.x uses the -n flag instead of -N to
# avoid creating the associated group.
nogroup='-N'
if test -f /etc/redhat-release; then
	read vendor release version < /etc/redhat-release 
	if test $vendor = CentOS; then
		nogroup='-n'
	fi
fi

if ${AWK} -F: -v jailuser="${jailuser}" 'BEGIN {status = 1} $1 == jailuser {status = 0} END {exit status}' /etc/passwd
then
    echo "You already have a user \"${jailuser}\", so I will use it."
elif /usr/sbin/useradd -g ${jailgroup} -M $nogroup -d "${jaildir}" -s /sbin/nologin -c "RPKI validation system" ${jailuser}
then
    echo "Added user \"${jailuser}\"."
else
    echo "Adding user \"${jailuser}\" failed..."
    echo "Please create it, then try again."
    exit 1
fi

# test for x86_64 target
if test -d /lib64; then
    libdir=/lib64
else
    libdir=/lib
fi
    
echo "Building directories"

if ! /bin/mkdir -p -v -m 555		\
    "${jaildir}/bin"			\
    "${jaildir}/dev"			\
    "${jaildir}/etc/trust-anchors"	\
    "${jaildir}/${libdir}"		\
    "${jaildir}/usr/lib"		\
    "${jaildir}/data"
then
    echo "Unable to build directories under \"${jaildir}\", please fix this then try again."
    exit 1
fi

echo "Installing device inodes"

if ! (cd /dev; /bin/ls null zero random urandom | /bin/cpio -puv "${jaildir}/dev")
then
    echo "Unable to install device inodes in ${jaildir}/dev/, please fix this then try again"
    exit 1
fi

echo "Copying files from /etc"

for i in /etc/localtime /etc/resolv.conf /etc/passwd /etc/group
do
    j="${jaildir}${i}"
    if test -r "$i" &&
	! /usr/bin/cmp -s "$i" "$j" &&
	! /bin/cp -p "$i" "$j"
    then
	echo "Unable to copy $i to ${jaildir}, please fix this then try again"
	exit 1
    fi
done

echo "Whacking file permissions"

if ! /bin/chmod -R a-w "${jaildir}/bin" "${jaildir}/etc" ||
   ! /bin/chmod -R 755 "${jaildir}/data" ||
   ! /bin/chown -R root:root "${jaildir}/bin" "${jaildir}/etc" ||
   ! /bin/chown -R "${jailuser}:${jailgroup}" "${jaildir}/data"
then
    echo "Unable to set file permissions and ownerships correctly, please fix this and try again"
    exit 1
fi

if test -f "${jaildir}/etc/rsa_key"
then
    /bin/chmod 400 "${jaildir}/etc/rsa_key"
    /bin/chown "${jailuser}" "${jaildir}/etc/rsa_key"
fi

if test -r "$jaildir/etc/rcynic.conf"; then
    echo "You already have config file \"${jaildir}/etc/rcynic.conf\", so I will use it."
elif /usr/bin/install -m 444 -o root -g root -p ../sample-rcynic.conf "${jaildir}/etc/rcynic.conf"; then
    echo "Installed minimal ${jaildir}/etc/rcynic.conf, adding SAMPLE trust anchors"
    for i in ../../sample-trust-anchors/*.tal; do
	j="$jaildir/etc/trust-anchors/${i##*/}"
	test -r "$i" || continue
	test -r "$j" && continue
	echo "Installing $i as $j"
	/usr/bin/install -m 444 -o root -g root -p "$i" "$j"
    done
    j=1
    for i in $jaildir/etc/trust-anchors/*.tal; do
	echo >>"${jaildir}/etc/rcynic.conf" "trust-anchor-locator.$j	= /etc/trust-anchors/${i##*/}"
	j=$((j+1))
    done
else
    echo "Installing minimal ${jaildir}/etc/rcynic.conf failed"
    exit 1
fi

echo "Installing rcynic as ${jaildir}/bin/rcynic"

/usr/bin/install -m 555 -o root -g root -p ../../rcynic "${jaildir}/bin/rcynic"

if test -x "$jaildir/bin/rsync"; then
    echo "You already have an executable \"$jaildir/bin/rsync\", so I will use it"
elif /usr/bin/install -m 555 -o root -g root -p /usr/bin/rsync "${jaildir}/bin/rsync"; then
    echo "Installed ${jaildir}/bin/rsync"
else
    echo "Installing ${jaildir}/bin/rsync failed"
    exit 1
fi

echo "Copying required shared libraries" 

shared_libraries="${jaildir}/bin/rcynic ${jaildir}/bin/rsync $(/usr/bin/find ${libdir} -name 'libnss*.so*' -print)"
while true
do
    closure="$(/usr/bin/ldd ${shared_libraries} |
	       ${AWK} -v "rcynic=${jaildir}/bin/rcynic" -v "rsync=${jaildir}/bin/rsync" '
		  {
			sub(/:$/, "");
		  }
		  $0 == rcynic || $0 == rsync || $1 ~ /\/ld-linux\.so/ {
			next;
		  }
		  {
			for (i = 1; i <= NF; i++)
			    if ($i ~ /^\//)
				print $i;
		  }
	       ' |
	       ${SORT} -u)"
    if test "x$shared_libraries" = "x$closure"
    then
	break
    else
	shared_libraries="$closure"
    fi
done

# Under CentOS 5.5, rsync requires libresolv, but ldd doesn't show
# it.
if test -f ${libdir}/libresolv.so.2; then
    shared_libraries="${shared_libraries} ${libdir}/libresolv.so.2"
fi

for shared in ${libdir}/*ld*.so* $shared_libraries
do
    if test -r "${jaildir}/${shared}"
    then
	echo "You already have a \"${jaildir}${shared}\", so I will use it"
    elif /usr/bin/install -m 555 -o root -g root -d "${jaildir}${shared%/*}" &&
	 /usr/bin/install -m 555 -o root -g root -p "${shared}" "${jaildir}${shared}"
    then
	echo "Copied ${shared} into ${jaildir}"
    else
        echo "Unable to copy ${shared} into ${jaildir}"
	exit 1
    fi
done

if /usr/bin/install -m 555 -o root -g root -p ../../rcynic-html "${jaildir}/bin/rcynic-html"; then
    echo "Installed rcynic.py as \"${jaildir}/bin/rcynic-html\""
else
    echo "Installing rcynic-html failed"
    exit 1
fi

echo "Setting up root's crontab to run jailed rcynic"

case "$setupcron" in
YES|yes)
    /usr/bin/crontab -l -u root 2>/dev/null |
    ${AWK} -v "jailuser=$jailuser" -v "jailgroup=$jailgroup" -v "jaildir=$jaildir" '
	BEGIN {
	    cmd = "exec /usr/sbin/chroot --userspec=" jailuser ":" jailgroup " " jaildir;
	    cmd = cmd " /bin/rcynic -c /etc/rcynic.conf";
	}
	$0 !~ cmd {
	    print;
	}
	END {
	    "/usr/bin/hexdump -n 2 -e \"\\\"%u\\\\\\n\\\"\" /dev/random" | getline;
	    printf "%u * * * *\t%s\n", $1 % 60, cmd;
	}' |
    /usr/bin/crontab -u root -
    /bin/cat <<EOF

	crontab is set up to run rcynic hourly, at a randomly selected
	minute (to spread load on the rsync servers).  Please do NOT
	adjust this to run on the hour.  In particular please do NOT
	adjust this to run at midnight UTC.
EOF
    ;;

*)
    /bin/cat <<EOF

	You'll need to add a crontab entry running one of the the following command as root:

	    /usr/sbin/chroot --userspec $jailuser:$jailgroup $jaildir /bin/rcynic -c /etc/rcynic.conf

	    /usr/bin/chrootuid $jaildir rcynic /bin/rcynic -c /etc/rcynic.conf

	We recommend the latter, as chrootuid has proven more reliable for us than the chroot
	program that is included on some GNU/Linux platforms.

	Please try to pick a random time for this, don't just run it on the hour,
	or at local midnight, or, worst of all, at midnight UTC.

EOF
    ;;

esac

/bin/cat <<EOF

	Jail set up. You may need to customize $jaildir/etc/rcynic.conf.
	If you did not install your own trust anchors, a default set
	of SAMPLE trust anchors may have been installed for you, but
	you, the relying party, are the only one who can decide
	whether you trust those anchors.  rcynic will not do anything
	useful without good trust anchors.

EOF