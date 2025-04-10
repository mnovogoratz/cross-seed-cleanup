# cross-seed-cleanup
Script checks if a seeding file is still present in library, if not delete.

Script is very ruidmentary, takes a long time to run, and not intended to be very versatile. I made it because I couldn't find something that did what I wanted, and it works fine for me.

THE IDEA:
I want to use cross-seed and make files available in my library as much as possible. I also don't want to waste a lot of space, and I don't want to go around pruning everything manually to clear up space. I couldn't find a readymade solution that:
1) identifies when a file is deleted from my library
2) checks to see if there is an associated hardlinked file being seeded
3) Verifies that the torrent has seeded for at least X days OR is labeled as a cross-seed.
4) deletes the torrent / associated files.

Prereqs:
This script works with a Transmission container running in docker. 
Your cross-seeds need to be labeled as "cross-seed".
The logic for identifying seeds for deletion relies on hardlinks being set up. If you do not use hard-links, this will just delete everything you are seeding assuming it has seeded for at least X days.

WHAT IT ACTUALLY DOES:
1) Cycles through every file located in the "search directory"
2) For every file in the "search directory" it checks to see if a hardlinked file exists in the "archive directory"
3) If there is no file in the "archive directory" it queries Transmission to determine what torrent contains the file in the search directory.
4) Once the torrent is identified, the seeding time for the torrent is retrieved and compared to the defined seeding time variable.
5) If the seeding time is greater than the amount specified OR if the torrent is labeled as a cross-seed, the torrent and associated files are deleted.

Setup:
All variables that you should need to define are at the top of the script, read the comments and make the necessary changes for your configuration. If you want to do a dryrun run with "-d" and it will just log what would be deleted (eg. command - ./cleanup.sh -d)

Improvement opportunities:
The part of the script that is very slow is the get_torrent_id_for_file() function. It works by individually querying each torrent ID in transmission for a file list, checks that list, and then determines if the file it is reviewing is present in that torrent or not. It also stops as soon as it finds a match, and doesn't look for additional torrents which are likely present due to cross-seeds. There surely is some optimization that could be done here, but it doesn't bother me enough to do anything about it because the script as is will eventually get everything.
