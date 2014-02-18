# Generic makefile for DVCS conversions using reposurgeon
#
# Steps to using this:
# 0. Copy this into a scratch directory as Makefile
# 1. Make sure git, reposurgeon, and repopuller are on your $PATH.
# 2. Set PROJECT to the name of your project
# 3. Set SOURCE_VCS to svn or cvs
# 4. Set TARGET_VCS to git, hg, or bzr
# 5. For svn, set SVN_URL to point at the remote repository you want to convert.
# 6. For cvs, set CVS_HOST to the repo hostname and CVS_MODULE to the module. 
# 7. Create a $(PROJECT).lift script for your custom commands, initially empty.
# 8. Run 'make stubmap' to create a stub author map.
# 9. Run 'make' to build a converted repository
#
# For a production-quality conversion you will need to edit the map
# file and the lift script.  During the process you can set EXTRAS to
# name extra metadata such as a comments mailbox.

PROJECT = foo
SOURCE_VCS = svn
TARGET_VCS = git
EXTRAS = 
SVN_URL = svn://svn.debian.org/$(PROJECT)
CVS_HOST = $(PROJECT).cvs.sourceforge.net
CVS_MODULE = $(PROJECT)
VERBOSITY = "verbose 1"

# Configuration ends here

.PHONY: local-clobber remote-clobber gitk gc compare clean dist map

default: $(PROJECT)-$(TARGET_VCS)

# Build the converted repo from the second-stage fast-import stream
$(PROJECT)-$(TARGET_VCS): $(PROJECT).fi
	rm -fr $(PROJECT)-$(TARGET_VCS); reposurgeon "read <$(PROJECT).fi" "prefer $(TARGET_VCS)" "rebuild $(PROJECT)-$(TARGET_VCS)"

# Build the second-stage fast-import stream from the first-stage stream dump
$(PROJECT).fi: $(PROJECT).$(SOURCE_VCS) $(PROJECT).lift $(PROJECT).map $(EXTRAS)
	reposurgeon $(VERBOSITY) "read <$(PROJECT).$(SOURCE_VCS)" "authors read <$(PROJECT).map" "prefer git" "script $(PROJECT).lift" "fossils write >$(PROJECT).fo" "write >$(PROJECT).fi"

# Force rebuild of first-stage stream from the local mirror on the next make
local-clobber: clean
	rm -fr $(PROJECT).fi $(PROJECT)-$(TARGET_VCS) *~ .rs* $(PROJECT)-conversion.tar.gz 

# Force full rebuild from the remote repo on the next make.
remote-clobber: local-clobber
	rm -fr $(PROJECT).$(SOURCE_VCS) $(PROJECT)-mirror $(PROJECT)-checkout

# Get the (empty) state of the author mapping from the first-stage stream
stubmap: $(PROJECT).$(SOURCE_VCS)
	reposurgeon "read <$(PROJECT).$(SOURCE_VCS)" "authors write >$(PROJECT).map"

# Source-VCS-specific productions to build the first-stage stream dump

ifeq ($(SOURCE_VCS),svn)

# Build the first-stage (Subversion) stream dump from the local mirror
$(PROJECT).svn: $(PROJECT)-mirror
	repopuller $(PROJECT)-mirror
	svnadmin dump $(PROJECT)-mirror/ >$(PROJECT).svn

# Build a local mirror of the remote Subversion repo
$(PROJECT)-mirror:
	repopuller $(SVN_URL)

# Make a local checkout of the Subversion mirror for inspection
$(PROJECT)-checkout: $(PROJECT)-mirror
	svn co file://${PWD}/$(PROJECT)-mirror $(PROJECT)-checkout

endif

ifeq ($(SOURCE_VCS),cvs)

# Mirror a CVS repo. Requires cvssync(1) from the cvs-fast-export
# distribution. You will need cvs-fast-export installed as well.
$(PROJECT)-mirror:
	cvssync -c -o $(PROJECT)-mirror "$(CVS_HOST):/cvsroot/$(PROJECT)" $(CVS_MODULE) 

# Build the first-stage CVS stream dump from the local mirror
$(PROJECT).cvs: $(PROJECT)-mirror
	find $(PROJECT)-mirror -name '*,v' | cvs-fast-export -k --reposurgeon >$(PROJECT).cvs

# Make a local checkout of the CVS mirror for inspection
$(PROJECT)-checkout: $(PROJECT)-mirror
	cvs co -Q -d:local:${PWD}/$(PROJECT)-mirror $(CVS_MODULE)
	mv $(CVS_MODULE) (PROJECT)-checkout

endif

ifeq ($(TARGET_VCS),git)

#
# The following productions are git-specific
#

# Browse the generated git repository
gitk: $(PROJECT)-git
	cd $(PROJECT)-git; gitk --all

# Run a garbage-collect on the generated git repository.  Import doesn't.
# This repack call is the active part of gc --aggressive.  This call is
# tuned for very large repositories.
gc: $(PROJECT)-git
	cd $(PROJECT)-git; time git -c pack.threads=1 repack -AdF --window=1250 --depth=250

# Make a conversion using a competing tool
$(PROJECT)-git-svn:
	git svn --stdlayout --no-metadata --authors-file=$(PROJECT).authormap clone file://${PWD}/$(PROJECT)-mirror $(PROJECT)-git-svn

# Compare file manifests on the master branch
compare: $(PROJECT)-git-svn $(PROJECT)-git
	@echo; echo "Comparing the directory manifests..."
	@rm -f GITSVN.MANIFEST PROJECTGIT.MANIFEST
	@(cd $(PROJECT)-git-svn >/dev/null; find . -type f | sort | fgrep -v '.git') >GITSVN.MANIFEST
	@(cd $(PROJECT)-git >/dev/null; find . -type f | sort | fgrep -v '.git') >PROJECTGIT.MANIFEST
	@echo "Comparing file manifests..."
	@diff -u GITSVN.MANIFEST PROJECTGIT.MANIFEST
	@echo "No diff output is good news"
	@echo; echo "Comparing file contents..."
	@set -e; for file in `cd $(PROJECT)-git-svn >/dev/null; git ls-files`; do cmp $(PROJECT)-git-svn/$$file $(PROJECT)-git/$$file; done
	@echo "No cmp output is good news"

# Compare all files in all revisions.  Ignore .gitignores, as reposurgeon
# makes them  but git-svn does not.
repodiffer: $(PROJECT)-git-svn $(PROJECT)-git
	repodiffer --ignore="gitignore,comment" --fossil-map=$(PROJECT).fo $(PROJECT)-git $(PROJECT)-git-svn | tee REPODIFFER.LOG

endif

# General cleanup and utility
clean:
	rm -fr *~ .rs* $(PROJECT)-conversion.tar.gz REPODIFFER.LOG

# Bundle up the conversion metadata for shipping
SOURCES = Makefile $(PROJECT).lift $(PROJECT).map $(EXTRAS)
$(PROJECT)-conversion.tar.gz: $(SOURCES)
	tar --dereference --transform 's:^:$(PROJECT)-conversion/:' -czvf $(PROJECT)-conversion.tar.gz $(SOURCES)

dist: $(PROJECT)-conversion.tar.gz

