!echo This exercises many delete cases in the test repo
repeat 1
read testrepo.dump
delete 8,9
coverage       # Expect this to show case 1 covered.
inspect
