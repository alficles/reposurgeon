## Test file expunge operation
verbose 1
echo 1
quiet on
read --nobranch <expunge.svn
expunge 1..$ ^releases/v1.0/
choose
