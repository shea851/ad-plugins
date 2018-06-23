# Author: Corporate
# Date: 20161109
# Random subroutines to make stuff work how I want

use warnings;

# Select NPC stats from DB
# Usage:
#	 my @npcBaseStats = plugin::NPCStatsDBLookupByID($npc->GetNPCTypeID());
#	 my $npcBaseHP = $npcBaseStats[0];
#	 my $npcBaseAC = $npcBaseStats[1];
#	 my $npcBaseMIN = $npcBaseStats[2];
#	 my $npcBaseMAX = $npcBaseStats[3];
#	 my $npcBaseSTR = $npcBaseStats[4];
#	 my $npcAccuracy = $npcBaseStats[5];
#
sub NPCStatsDBLookupByID
{
	my $npcDBID = $_[0];
	my @npcStats;
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT hp, AC, mindmg, maxdmg, STR, Accuracy FROM npc_types WHERE id = ?;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($npcDBID);
	@npcStats = $query_handle->fetchrow_array();
	
	return @npcStats;
}


# Select Fabled DB ID by Regular NPC version name
# Usage:
#    my $npc = plugin::val('$npc');
#    my $fabledID = plugin::FabledIDDBLookupByRegularName($npc);
#
sub FabledIDDBLookupByRegularName
{
	my $npc = $_[0];
	my $fabledID = 0;
	
	my $formatNpcName = $npc->GetCleanName();
	$formatNpcName =~ s/^a (.*)/$1/g; #remove leading "a "
	$formatNpcName =~ s/^an (.*)/$1/g; #remove leading "an "
	$formatNpcName =~ s/^the (.*)/$1/g; #remove leading "the "
	$formatNpcName =~ s/ /_/g; #replace spaces with underscores
	
	if (length($formatNpcName) != 0)
	{
		my $connect = plugin::LoadMysql();
		my $query = "SELECT id FROM npc_types WHERE name LIKE ?;";
		my $query_handle = $connect->prepare($query);
		$query_handle->execute('%fabled%'.$formatNpcName.'%');
		while (my @row = $query_handle->fetchrow_array())
		{
			$fabledID = $row[0];
		}
	}
	
	return $fabledID;
}


# Spawn fabled version of mob if it exists in DB on kill
# Usage:
#    plugin::SpawnFabled() within sub EVENT_DEATH_COMPLETE
sub SpawnFabled
{	
	# set to 100 for testing
	my $spawnChanceLowLevel = 12;
	my $spawnChanceHighLevel = 6;
	my $npc = plugin::val('$npc');
	my $x = plugin::val('$x');
	my $y = plugin::val('$y');
	my $z = plugin::val('$z');
	my $h = plugin::val('$h');
	
	my $spawnChance = 0;
	
	# Determine if low level npc and double fabled rate
	if ($npc->GetLevel() <= 50)
	{
		$spawnChance = $spawnChanceLowLevel;
	}
	else
	{
		$spawnChance = $spawnChanceHighLevel;
	}
	
	my $fabledID = FabledIDDBLookupByRegularName($npc);	
	
	# Do random math and spawn Fabled or nothing
	my $randomResult = int(rand(100));
	if ($randomResult < $spawnChance && $fabledID != 0)
	{
		quest::say("you aren't done with me yet!");
		quest::spawn2($fabledID, 0, 0, $x, $y, $z, $h);
	}
	else
	{
		quest::emote("lays dead at your feet.");
	}
}


# Log progression kills in table ad_last_kill
# Usage:
#	 LogProgressionKill($npc->GetNPCTypeID(), $npc->GetCleanName(), $npc->GetZoneID(), $client->GetName());
sub LogProgressionKill
{
	my $npc_id = $_[0];
	my $npc_name = $_[1];
	my $zone_id = $_[2];
	my $client_name = $_[3];
	
	my $connect = plugin::LoadMysql();
	
	my $checkQuery = "SELECT * FROM ad_last_kill WHERE npc_id = $npc_id AND last_kill_time > DATE_ADD(NOW(), INTERVAL -10 SECOND);";
	my $updateQuery = "UPDATE ad_last_kill SET flagged_players = CONCAT(flagged_players, ',$client_name') WHERE npc_id = $npc_id;";
	my $replaceQuery = "REPLACE INTO ad_last_kill (npc_id, npc_name, zone_id, flagged_players, last_kill_time) VALUES ($npc_id, '$npc_name', $zone_id, '$client_name', NOW());";
	
	# Check and see if update or replace needs to occur
	my $query_handle = $connect->prepare($checkQuery);
	$query_handle->execute();
	
	if ($query_handle->fetchrow_array())
	{
		# Row exists, update name only
		$query_handle = $connect->prepare($updateQuery);
		$query_handle->execute();
	}
	else
	{
		# Row doesn't exist, replace entire row
		$query_handle = $connect->prepare($replaceQuery);
		$query_handle->execute();
	}
	
	return;
}


# Give "flag" in form of quest global on kill
# Usage:
#    plugin::KillMerit() within sub EVENT_KILLED_MERIT
sub KillMerit
{
	my $entity_list = plugin::val('$entity_list');
	my $client = plugin::val('$client');
	my $npc = plugin::val('$npc');
    my $slain = $npc->GetCleanName();

	if ($client->GetRaid())
	{
		if ($client->GetZoneID() == $npc->GetZoneID())
		{
			$client->SetGlobal($slain,1,5,"F");
			$client->SendMarqueeMessage(15, 510, 1, 1, 6000, "Your raid received credit for killing ".$slain.".");
			$client->Message(15, "Your raid received credit for killing ".$slain.".");
		}
	}	
    else
	{
		$client->SetGlobal($slain,1,5,"F");
		$client->SendMarqueeMessage(15, 510, 1, 1, 6000, "Your group received credit for killing ".$slain.".");
		$client->Message(15, "Your group received credit for killing ".$slain.".");
    }
	
	LogProgressionKill($npc->GetNPCTypeID(), $npc->GetCleanName(), $npc->GetZoneID(), $client->GetName());
}


sub TimeToQglobalExpiration
{
	my $return = "";
	my $qglob = $_[0];
	my $connect = plugin::LoadMysql();
	my $query = "SELECT expdate FROM quest_globals WHERE name = ? LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($qglob);
	while (my @row = $query_handle->fetchrow_array())
	{
		$endtime = $row[0];
	}
	
	my $timeDiff = abs(time - $endtime);
	
	if ($timeDiff > 7200) {
		$hoursLeft = int($timeDiff / 3600);
		return "over ".$hoursLeft." hours left";		
	}
	elsif ($timeDiff > 3600) {
		return "over 1 hour left";
	}
	elsif ($timeDiff > 0) {
		return "less than 1 hour left";
	}
}


# Accurately look up qglobal value when qglobal is newly added (before zone recycle)
# Usage:
#    plugin::ReadQGlobal("qglobalname")
# You can use in if (not defined...)
sub ReadQGlobal
{
	my $qglob = $_[0];
	my $connect = plugin::LoadMysql();
	my $query = "SELECT value FROM quest_globals WHERE name = ? LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($qglob);
	
	while (my @row = $query_handle->fetchrow_array())
	{
		return $row[0];
	}
	
	return;
}


sub ReadVariable
{
	my $val = $_[0];
	my $connect = plugin::LoadMysql();
	my $query = "SELECT value FROM variables WHERE varname LIKE ?;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($val);
	
	while (my @row = $query_handle->fetchrow_array())
	{
		return @row;
	}
	
	return;
}


sub DeleteVariable
{
	my $val = $_[0];
	my $connect = plugin::LoadMysql();
	my $query = "DELETE FROM variables WHERE value = ?;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($val);
	
	return;
}


# Check if zone requires a flag
# Usage:
#    plugin::CheckIfZoneHasFlag($zoneid)
# Returns: 1 if zone requires flag, 0 if zone does not
sub CheckIfZoneHasFlag
{
	my $val = $_[0];
	my $connect = plugin::LoadMysql();
	my $query = "SELECT flag_needed FROM zone WHERE zoneidnumber = ? LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($val);
	
	while (my @row = $query_handle->fetchrow_array())
	{
		if ($row[0] eq 1) {
			return 1;
		}
		elsif (!$row[0])
		{
			return 0;
		}
	}
	
	return;
}


# Get Faction Names by player ID
# Usage:
#	plugin::GetFactionNamesByID($charid)
sub GetFactionNamesByID
{
	my $val = $_[0];
	my @factionNames;
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT faction_list.name FROM faction_values, faction_list WHERE faction_values.faction_id = faction_list.id AND char_id = ?;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($val);

	while (my @row = $query_handle->fetchrow_array())
	{
		push(@factionNames, $row[0]);
	}
	
	return @factionNames;
}


# Get Faction ID by faction name
# Usage:
#	plugin::GetFactionIDByName("faction id")
sub GetFactionIDByName
{
	my $val = $_[0];
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT id FROM faction_list WHERE name = ? LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute($val);
	
	while (my @row = $query_handle->fetchrow_array())
	{
		return $row[0];
	}
	
	return;
}


sub GetFactionText
{
	my $val = $_[0];
	my $returnText;
		
	if    ($val >= 1101)                 { $returnText = "Ally"; }
	elsif ($val >= 701 && $val <= 1100)  { $returnText = "Warmly"; }
	elsif ($val >= 401 && $val <= 700)   { $returnText = "Kindly"; }
	elsif ($val >= 101 && $val <= 400)   { $returnText = "Amiable"; }
	elsif ($val >= 0 && $val <= 100)     { $returnText = "Indifferent"; }
	elsif ($val <= -1 && $val >= -100)   { $returnText = "Apprehensive"; }
	elsif ($val <= -101 && $val >= -700) { $returnText = "Dubious"; }
	elsif ($val <= -701 && $val >= -999) { $returnText = "Threatening"; }
	elsif ($val <= -1000)                { $returnText = "Ready to attack"; }
	else                                 { $returnText = "Unknown"; }
	
	return $returnText;
}


sub RemoveCharacterFromInstance
{
	my $charid = plugin::val('$charid');
	
	if ($charid > 0)
	{
		my $connect = plugin::LoadMysql();
		my $query = "DELETE FROM instance_list_player WHERE charid = ?;";
		my $query_handle = $connect->prepare($query);
		$query_handle->execute($charid);
	}
	
	return;
}


######################################
## INSTANCE MANAGEMENT              ##
## Author: Corporate                ##
## Why: PEQ potime scripts are shit ##
######################################

# Usage: plugin::AD_AddRaidInstance($client->GetRaid()->GetID(), $instanceZoneId, $raidInstanceID, << time valid in seconds >>);
sub AD_AddRaidInstance
{
	my $raidID = $_[0];
	my $zoneID = $_[1];
	my $instanceID = $_[2];
	my $secondsValid = $_[3];

	my $expdate = time() + $secondsValid;
	
	my $connect = plugin::LoadMysql();
	my $query = "INSERT INTO ad_instance_data (raidid, zoneid, instanceid, phase, stage, step, expdate) VALUES ($raidID, $zoneID, $instanceID, 0, 0, 0, $expdate);";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	return;
}


# Usage: plugin::AD_GetRaidInstanceId($client->GetRaid()->GetID(), $instanceZoneId);
sub AD_GetRaidInstanceId
{
	my $raidID = $_[0];
	my $zoneID = $_[1];
	
	AD_PurgeExpiredInstanceData();
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT instanceid FROM ad_instance_data WHERE raidid = $raidID AND zoneid = $zoneID LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	while (my @row = $query_handle->fetchrow_array())
	{
		return $row[0];
	}
	
	return 0;
}


# Usage: plugin::AD_GetRaidInstanceTimeRemaining($client->GetRaid()->GetID(), $instanceZoneId);
sub AD_GetRaidInstanceTimeRemaining
{
	my $raidID = $_[0];
	my $zoneID = $_[1];
	
	AD_PurgeExpiredInstanceData();
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT expdate FROM ad_instance_data WHERE raidid = $raidID AND zoneid = $zoneID LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	my $remainingSeconds = 0;

	while (my @row = $query_handle->fetchrow_array())
	{
		$remainingSeconds = $row[0] - time();
	}
	
	my $returnTime = AD_RemainingSecondsConversion($remainingSeconds);
	
	return $returnTime;
}


# Usage: plugin::AD_UpdateRaidInstanceProgress($instanceZoneId, $raidInstanceID, << phase|stage|step >>, << increment value >>);
sub AD_UpdateRaidInstanceProgress
{
	my $zoneID = $_[0];
	my $instanceID = $_[1]; # Force lookup of this first via get sub to purge expired
	my $progressColumn = $_[2];
	my $incrementValue = $_[3];
	
	my $connect = plugin::LoadMysql();
	my $query = "UPDATE ad_instance_data SET $progressColumn = $incrementValue WHERE zoneid = $zoneID AND instanceid = $instanceID;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();

	return;
}


# Usage: plugin::AD_GetRaidInstanceProgress($instanceZoneID, $raidInstanceID, << phase|stage|step >>);
sub AD_GetRaidInstanceProgress
{
	my $zoneID = $_[0];
	my $instanceID = $_[1];
	my $progressColumn = $_[2];
	
	AD_PurgeExpiredInstanceData();
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT $progressColumn FROM ad_instance_data WHERE zoneid = $zoneID AND instanceid = $instanceID LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	while (my @row = $query_handle->fetchrow_array())
	{
		return $row[0];
	}
	
	return 0;
}


# Usage: AD_PurgeExpiredInstanceData();
sub AD_PurgeExpiredInstanceData
{
	my $currentTime = time();
	
	my $connect = plugin::LoadMysql();
	my $query = "DELETE FROM ad_instance_data WHERE expdate < $currentTime;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	return;
}


# Usage: plugin::AD_AddInstanceLockout($charid, $instanceZoneId, << notes >>, << lockout time in seconds >>);
sub AD_AddInstanceLockout
{
	my $charID = $_[0];
	my $zoneID = $_[1];
	my $notes = $_[2];
	my $secondsValid = $_[3];

	my $expdate = time() + $secondsValid;
	
	my $connect = plugin::LoadMysql();
	my $query = "INSERT INTO ad_instance_lockout (charid, zoneid, notes, expdate) VALUES ($charID, $zoneID, '$notes', $expdate) ON DUPLICATE KEY UPDATE expdate=$expdate;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	return;
}


sub AD_CheckInstanceLockout
{
	my $charID = $_[0];
	my $zoneID = $_[1];
	
	AD_PurgeExpiredInstanceLockouts();
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT count(*) FROM ad_instance_lockout WHERE charid = $charID AND zoneid = $zoneID;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	while (my @row = $query_handle->fetchrow_array())
	{
		return $row[0];
	}
	
	return 0;
}


# Usage: plugin::AD_GetInstanceLockoutTimeRemaining($charid, $instanceZoneId);
sub AD_GetInstanceLockoutTimeRemaining
{
	my $charID = $_[0];
	my $zoneID = $_[1];
	
	AD_PurgeExpiredInstanceLockouts();
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT expdate FROM ad_instance_lockout WHERE charid = $charID AND zoneid = $zoneID LIMIT 1;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	my $remainingSeconds = 0;

	while (my @row = $query_handle->fetchrow_array())
	{
		$remainingSeconds = $row[0] - time();
	}
	
	my $returnTime = AD_RemainingSecondsConversion($remainingSeconds);
	
	return $returnTime;
}


# Usage: AD_PurgeExpiredInstanceLockouts();
sub AD_PurgeExpiredInstanceLockouts
{
	my $currentTime = time();
	
	my $connect = plugin::LoadMysql();
	my $query = "DELETE FROM ad_instance_lockout WHERE expdate < $currentTime;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	return;
}


# Usage: AD_RemainingSecondsConversion($remainingSeconds);
# Returns: Human readable time string for clients
sub AD_RemainingSecondsConversion
{
	my $remainingSeconds = $_[0];
	my $returnTime = 0;
	
	if ($remainingSeconds > 0)
	{
		my $returnHours = 0;
		my $returnMins = 0;
	
		my $hours = int($remainingSeconds / 3600); # Get hours
		my $mins = int(($remainingSeconds / 60) - ($hours * 60)); # Get minutes remaining (59 or less)
		
		# Plural logic
		if ($hours == 1) {$returnHours = $hours." hour";}
		elsif ($hours > 1) {$returnHours = $hours." hours";}
		if ($mins == 1) {$returnMins = $mins." minute";}
		elsif ($mins > 1) {$returnMins = $mins." minutes";}
		
		# And word logic
		if ($hours > 0 && $mins > 0) {$returnTime = $returnHours." and ".$returnMins;}
		elsif ($hours > 0 && $mins == 0) {$returnTime = $returnHours;}
		elsif ($hours == 0 && $mins > 0) {$returnTime = $returnMins;}
	}
	
	return $returnTime;
}


# Usage: AD_GetCharIDsInInstance($raidInstanceID);
# Returns: Array of character IDs that are part of the instance specified
sub AD_GetCharIDsInInstance
{
	my $instanceID = $_[0];
	
	my $connect = plugin::LoadMysql();
	my $query = "SELECT charid FROM instance_list_player WHERE id = $instanceID;";
	my $query_handle = $connect->prepare($query);
	$query_handle->execute();
	
	my @returnArr;
	
	while (my @row = $query_handle->fetchrow_array())
	{
		push (@returnArr, $row[0]);
	}
	
	return @returnArr;
}


return 1;
