#! /bin/bash

set -e

# options may be followed by one colon to indicate they have a required argument
if ! options=$(getopt -o dEf -l ignore-dependencies,force,no-rdoc,rdoc,no-ri,ri,env-shebang,no-env-shebang,symlink-binaries,default-gem:,build-root:,doc-files:,gem-name:,gem-version:,gem-suffix: -- "$@")
then
    # something went wrong, getopt will put out an error message for us
    exit 1
fi

eval set -- "$options"

gem_binary="/usr/bin/gem.*"
defaultgem=
gemfile=
otheropts=
buildroot=
docfiles=
gemname=
gemversion=
gemsuffix=
ua_dir="/etc/alternatives"
docdir="/usr/share/doc/packages"
# once we start fixing packages set this to true
symlinkbinaries="false"

while [ $# -gt 0 ]
do
    case $1 in
    --default-gem) defaultgem=$2 ; shift;;
    --gem-binary) gem_binary="$2" ; shift;;
    --doc-files) docfiles="$2" ; shift;;
    --gem-name) gemname="$2" ; shift;;
    --gem-version) gemversion="$2" ; shift;;
    --gem-suffix) gemsuffix="$2" ; shift;;
    --symlink-binaries) symlinkbinaries="true" ;;
    --build-root) otheropts="$otheropts $1=$2"; buildroot=$2; shift;;
    (--) ;;
    (-*) otheropts="$otheropts $1";;
    (*) gemfile=$1; otheropts="$otheropts $1"; break;;
    esac
    shift
done

if [ "x$gemfile" = "x" ] ; then 
  gemfile=$(find . -maxdepth 2 -type f -name "$defaultgem")
  # if still empty, we pick the sources
  if [ "x$gemfile" = "x" ] ; then
    gemfile=$(find $RPM_SOURCE_DIR -name "$defaultgem")
  fi
  otheropts="$otheropts $gemfile"
fi
set -x

mkdir -p "${RPM_BUILD_ROOT}${ua_dir}"
mkdir -p "${RPM_BUILD_ROOT}$docdir"

for gem in $gem_binary ; do
  $gem install --verbose --local $otheropts
  # get the ruby interpreter
  ruby="${gem#/usr/bin/gem.}"
  rpmname="${ruby}-rubygem-${gemname}${gemsuffix:+$gemsuffix}"
  if test -d $RPM_BUILD_ROOT/usr/bin; then
    pushd $RPM_BUILD_ROOT/usr/bin
    if [ "x$symlinkbinaries" = "xtrue" ] ; then
      for i in *$ruby ; do
        unversioned="${i%.$ruby}"
        mv -v ${i} ${i}-${gemversion}
        ruby -p -i -e "\$_.gsub!(/>= 0/, '= $gemversion')" ${i}-${gemversion}
        if [ ! -L ${RPM_BUILD_ROOT}${ua_dir}/${unversioned} ] ; then
          ln -sv ${unversioned} ${RPM_BUILD_ROOT}${ua_dir}/${unversioned}
        fi
        # unversioned
        if [ ! -L $unversioned ] ; then
          ln -sv ${ua_dir}/${unversioned} $unversioned
        fi

        # ruby versioned
        if [ ! -L ${RPM_BUILD_ROOT}${ua_dir}/${i} ] ; then
          ln -sv ${i} ${RPM_BUILD_ROOT}${ua_dir}/$i
        fi
        if [ ! -L $i ] ; then
          ln -sv ${ua_dir}/${i} $i
        fi
        # gem versioned
        if [ ! -L ${RPM_BUILD_ROOT}${ua_dir}/$unversioned-$gemversion ] ; then
          ln -sv ${unversioned}-$gemversion ${RPM_BUILD_ROOT}${ua_dir}/$unversioned-$gemversion
        fi
        if [ ! -L $unversioned-$gemversion ] ; then
          ln -sv ${ua_dir}/${unversioned}-$gemversion $unversioned-$gemversion
        fi
      done ;
    else
      for i in *$ruby ; do
        # lets undo the format-executable to avoid breaking more spec files
        unversioned="${i%.$ruby}"
        mv -v $i $unversioned 
      done
    fi
    popd
  fi
  gemdir="$($gem env gemdir)"
  if [ "x$docfiles" != "x" ] ; then
    mkdir -p "${RPM_BUILD_ROOT}${docdir}/${rpmname}"
    for i in $docfiles ; do
      ln -sfv "${gemdir}/gems/${gemname}-${gemversion}/${i}" "${RPM_BUILD_ROOT}${docdir}/${rpmname}/${i}"
    done
  fi
  if [ -d "$buildroot" ]; then
    find ${buildroot}${gemdir} -type f -perm /u+x | while read file; do
      # TODO: scripts in ruby/1.9.1 should call ruby1.9 for consistency
      sed -i -e "s,^#!/usr/bin/env ruby,#!/usr/bin/ruby,; s,^#! *[^ ]*/ruby\S\+,#!/usr/bin/ruby.$ruby," "$file"
    done
    # some windows made gems are broken
    find $buildroot -ls
    chmod -R u+w $buildroot
    chmod -R o-w $buildroot
  fi
done