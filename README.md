# cross-seed-cleanup
Script checks if a seeding file is still present in library, if not delete.

Script is very ruidmentary, takes a long time to run, and not intended to be very versatile. I made it because I couldn't find something that did what I wanted, and it works fine for me.

THE IDEA:
I want to use cross-seed and make files available in my library as much as possible. I also don't want to waste a lot of space, and I don't want to go around pruning everything manually to clear up space. I couldn't find a readymade solution that:
1) identifies when a file is deleted from my library
2) checks to see if there is an associated hardlinked file being seeded
3) Verifies that the torrent has seeded for at least X days OR is labeled as a cross-seed.
4) deletes the torrent / associated file when it identifies there is no hardlinked file in the library.

Prereqs:
This script works with a Transmission container running in docker. 
Your cross-seeds need to be labeled as "cross-seed".
The logic for identifying seeds for deletion relies on hardlinks being set up. If you do not use hard-links, this will just delete everything you are seeding assuming it has seeded for at least X days.

Setup:
All variables that you should need to define are at the top of the script, read the comments and make the necessary changes for your configuration. If you want to do a dryrun run with "-d" and it will just log what would be deleted (eg. command - ./cross-seed-cleanup.sh -d)
