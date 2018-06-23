#checks to see if player has item
#useage plugin::check_hasitem($client, itemid);
sub check_hasitem {
    my $client = shift;
    my $itemid = shift;

	my @slots = (0..30, 251..340, 2000..2023, 2030..2270, 2500..2501, 2531..2550, 9999);
	foreach $slot (@slots) {
		if ($client->GetItemIDAt($slot) == $itemid) {
			return 1;
		}

		for ($i = 0; $i < 5; $i++) {
			if ($client->GetAugmentIDAt($slot, $i) == $itemid) {
				return 1;
			}
		}
    }
	return 0;
}

1;