#!/usr/bin/perl
#
########################################################
#
# oracle_rac_services.pl
#
# Checkmk agent plugin for Oracle RAC / CRS monitoring.
# Self-contained: all functions inlined, no library deps.
#
# Metrics collected:
#   5000 - CRS health       (crsctl check crs)
#   5010 - Voting disks     (crsctl query css votedisk)
#   5020 - CRS resource     (crsctl stat res ...)
#   5030 - OCR integrity    (ocrcheck)
#
# Output format (sep=124 i.e. pipe):
#   <<<oracle_rac_services:sep(124)>>>
#   SID|METRIC|VALUE|OPTION1|OPTION2|OPTION3|OPTION4|OPTION5
#
########################################################

use strict;
use warnings;

our $PROGRAMNAME = "oracle_rac_services.pl";

# Number of voting disks expected (can be overridden below)
my $EXPECTED_VOTING_DISKS = 3;

##################################################################
# Inlined utility functions (from oramp_genlib / oramp_cfglib)
##################################################################

sub is_windows { return ( $^O eq "MSWin32" ) ? 1 : 0; }
sub is_unix    { return ( $^O =~ /hpux|linux|aix|solaris/ ) ? 1 : 0; }

sub trim
{
    my @out = @_;
    for (@out)
    {
        if ( defined $_ )
        {
            s/^\s+//;
            s/\s+$//;
        }
    }
    return wantarray ? @out : $out[0];
}

# Normalise path separators and collapse duplicate slashes/backslashes.
sub make_ospath
{
    my $path = $_[0];
    return "" unless defined $path;
    chomp $path;
    $path =~ s/"//g;
    if ( is_windows() )
    {
        $path =~ s/\//\\/g;
        $path =~ s/\\{2,}/\\/g;
    }
    else
    {
        $path =~ s/\/{2,}/\//g;
    }
    return $path;
}

# Sanitise a string for pipe-delimited output: replace literal '|' with '?'
# so it cannot break the field structure expected by parse_oracle().
sub sanitise_option
{
    my $s = defined $_[0] ? $_[0] : "";
    $s =~ s/\|/?/g;
    return $s;
}

# Truncate long strings and append an ellipsis.
sub truncate_str
{
    my ( $s, $max ) = @_;
    $max //= 512;
    if ( length($s) > $max )
    {
        $s = substr( $s, 0, $max - 4 ) . " ...";
    }
    return $s;
}

##################################################################
# Grid Home discovery
# Strategy (in order):
#   1. $GRID_HOME env var
#   2. /etc/oratab or /var/opt/oracle/oratab  (lines with +ASM*)
#   3. oraInventory ContentsXML/inventory.xml (HOME entries)
# Returns: ({ SID => ..., ORAHOME => ... }, ...) as list of hashrefs
##################################################################

sub read_oratab
{
    my $oratab = "";
    for my $candidate ( "/etc/oratab", "/var/opt/oracle/oratab" )
    {
        if ( -r $candidate )
        {
            $oratab = $candidate;
            last;
        }
    }
    my @entries;
    return @entries unless $oratab;

    open( my $fh, "<", $oratab ) or return @entries;
    while (<$fh>)
    {
        chomp;
        s/^\s+//; s/#.*//; s/\s+$//;
        next unless length;
        my ( $sid, $home ) = split( /:/, $_, 3 );
        next unless defined $sid && defined $home;
        $sid  = trim($sid);
        $home = trim($home);
        push @entries, { SID => $sid, ORAHOME => $home };
    }
    close($fh);
    return @entries;
}

sub has_crsctl
{
    my $orahome = $_[0];
    my $crsctl = make_ospath( $orahome . "/bin/crsctl" . ( is_windows() ? ".exe" : "" ) );
    return -e $crsctl ? 1 : 0;
}

# Returns a hashref { SID => ..., ORAHOME => ... } for the active ASM/Grid home,
# or undef if none is found.
sub find_grid_config
{
    # 1. Explicit env override
    if ( $ENV{GRID_HOME} && has_crsctl( $ENV{GRID_HOME} ) )
    {
        my $sid = $ENV{ORACLE_SID} || "+ASM";
        return { SID => $sid, ORAHOME => $ENV{GRID_HOME} };
    }

    # 2. oratab: prefer lines whose SID starts with '+' (ASM / Grid)
    my @oratab = read_oratab();
    for my $entry (@oratab)
    {
        if ( $entry->{SID} =~ /^\+/ && has_crsctl( $entry->{ORAHOME} ) )
        {
            return $entry;
        }
    }

    # 3. oratab: any entry where ORACLE_HOME contains crsctl
    for my $entry (@oratab)
    {
        if ( has_crsctl( $entry->{ORAHOME} ) )
        {
            return $entry;
        }
    }

    return undef;
}

##################################################################
# Run an Oracle command and return ref to array of output lines.
# Returns undef on failure to open the pipe.
##################################################################
sub execute_oracle_command
{
    my ( $cmd, $options ) = @_;
    my @cmd_output;
    $options //= "";
    unless ( -e $cmd )
    {
        warn "$PROGRAMNAME: command not found: '$cmd'\n";
        return undef;
    }
    if ( open( my $pipe, "$cmd $options |" ) )
    {
        while (<$pipe>)
        {
            chomp;
            push @cmd_output, $_;
        }
        close($pipe);
    }
    else
    {
        warn "$PROGRAMNAME: failed to execute '$cmd $options': $!\n";
        return undef;
    }
    return \@cmd_output;
}

##################################################################
# Metric implementations (logic preserved from oramp_crs.pl,
# output changed to pipe-delimited Checkmk format)
#
# Each returns a list of hashrefs:
#   { OBJECT => $sid, NUMBER => $metric_num,
#     VALUE  => $res,  OPTION1 => $text }
##################################################################

# 5000 - crsctl check crs
# Value: 0 = healthy, 1 = error found
sub metric5000
{
    my $config  = $_[0];
    my $orahome = $config->{ORAHOME};
    my $sid     = $config->{SID};

    my $cmd    = make_ospath( $orahome . "/bin/crsctl" . ( is_windows() ? ".exe" : "" ) );
    my $output = execute_oracle_command( $cmd, "check crs" );

    my ( $res, $errorline ) = ( 0, "" );
    if ( defined $output )
    {
        for ( my $i = 0; $i < scalar @{$output}; $i++ )
        {
            if ( $output->[$i] =~ /(Cannot|Failure)/i )
            {
                $errorline = $i > 0
                    ? $output->[ $i - 1 ] . " " . $output->[$i]
                    : $output->[$i];
                $res = 1;
                last;
            }
        }
    }
    else
    {
        $res = 1;
        $errorline = "crsctl command not available";
    }

    return { OBJECT => $sid, NUMBER => 5000, VALUE => $res,
             OPTION1 => "ERRORLINE=" . truncate_str( sanitise_option($errorline) ) };
}

# 5010 - crsctl query css votedisk
# Value: 0 = expected number of voting disks found, 1 = mismatch
sub metric5010
{
    my $config  = $_[0];
    my $orahome = $config->{ORAHOME};
    my $sid     = $config->{SID};

    my $cmd    = make_ospath( $orahome . "/bin/crsctl" . ( is_windows() ? ".exe" : "" ) );
    my $output = execute_oracle_command( $cmd, "query css votedisk" );

    my $expected  = $EXPECTED_VOTING_DISKS;
    my $res       = 1;
    my $errorline = "Not found: 'Located $expected voting disk'";

    if ( defined $output )
    {
        for ( @{$output} )
        {
            if (/Located $expected voting disk/)
            {
                $res       = 0;
                $errorline = "";
                last;
            }
        }
    }
    else
    {
        $errorline = "crsctl command not available";
    }

    return { OBJECT => $sid, NUMBER => 5010, VALUE => $res,
             OPTION1 => "ERRORLINE=" . truncate_str( sanitise_option($errorline) ) };
}

# 5015 - crsctl query css votedisk: actual count of voting disks found
# Value: N = disk count; -1 = line not found or command failed
sub metric5015
{
    my $config  = $_[0];
    my $orahome = $config->{ORAHOME};
    my $sid     = $config->{SID};

    my $cmd    = make_ospath( $orahome . "/bin/crsctl" . ( is_windows() ? ".exe" : "" ) );
    my $output = execute_oracle_command( $cmd, "query css votedisk" );

    my ( $res, $detail ) = ( -1, "" );

    if ( defined $output )
    {
        for ( @{$output} )
        {
            if ( /Located (\d+) voting disk/ )
            {
                $res    = $1 + 0;
                $detail = trim($_);
                last;
            }
        }
    }

    # Always emit a record; -1 signals "data unavailable" and will trigger MIN threshold.
    return { OBJECT => $sid, NUMBER => 5015, VALUE => $res,
             OPTION1 => "LINE=" . truncate_str( sanitise_option($detail) ) };
}

# 5020 - crsctl stat res: resources targeted ONLINE but not ONLINE
# Value: count of such resources (0 = healthy)
sub metric5020
{
    my $config  = $_[0];
    my $orahome = $config->{ORAHOME};
    my $sid     = $config->{SID};

    my $cmd    = make_ospath( $orahome . "/bin/crsctl" . ( is_windows() ? ".exe" : "" ) );
    my $output = execute_oracle_command( $cmd,
        "stat res -w '(TARGET = ONLINE) AND (STATE != ONLINE)' -v" );

    my ( $res, $errorline ) = ( 0, "" );

    if ( defined $output )
    {
        my ( @records, $resource );
        for ( my $i = 0; $i < scalar @{$output}; $i++ )
        {
            if ( $output->[$i] =~ /^NAME=(.*)/ )
            {
                $resource         = {};
                $resource->{NAME} = trim($1);
                push @records, $resource;
            }
            elsif ( $output->[$i] =~ /^TARGET_SERVER=(.*)/ )
            {
                $resource->{TARGET_SERVER} = trim($1);
            }
            elsif ( $output->[$i] =~ /^STATE=(.*)/ )
            {
                $resource->{STATE} = trim($1);
            }
        }
        for my $rec (@records)
        {
            if ( exists $rec->{TARGET_SERVER} && $rec->{TARGET_SERVER} =~ /^\w/ )
            {
                my $msg = $rec->{NAME} . ":" . $rec->{TARGET_SERVER} . ":"
                    . ( $rec->{STATE} || "" );
                $errorline .= ( $errorline ? "; " : "" ) . $msg;
                $res++;
            }
        }
    }
    else
    {
        $res       = 1;
        $errorline = "crsctl command not available";
    }

    return { OBJECT => $sid, NUMBER => 5020, VALUE => $res,
             OPTION1 => "ERRORLINE=" . truncate_str( sanitise_option($errorline) ) };
}

# 5030 - ocrcheck integrity
# Value: 0 = healthy, 1 = one or more checks failed
sub metric5030
{
    my $config  = $_[0];
    my $orahome = $config->{ORAHOME};
    my $sid     = $config->{SID};

    my $cmd    = make_ospath( $orahome . "/bin/ocrcheck" . ( is_windows() ? ".exe" : "" ) );
    my $output = execute_oracle_command( $cmd, "" );

    my $res       = 0;
    my $errorline = "";
    my %required  = (
        "Device/File integrity check succeeded"     => 0,
        "Cluster registry integrity check succeeded" => 0,
    );

    if ( defined $output )
    {
        for my $line ( @{$output} )
        {
            for my $match ( keys %required )
            {
                $required{$match}++ if $line =~ /\Q$match\E/;
            }
        }
        for my $match ( keys %required )
        {
            if ( $required{$match} == 0 )
            {
                $res = 1;
                $errorline .= ( $errorline ? ", '" : "Not found: '" ) . $match . "'";
            }
        }
    }
    else
    {
        $res       = 1;
        $errorline = "ocrcheck command not available";
    }

    return { OBJECT => $sid, NUMBER => 5030, VALUE => $res,
             OPTION1 => "ERRORLINE=" . truncate_str( sanitise_option($errorline) ) };
}

##################################################################
# Format one metric result as a pipe-delimited output line.
# Fields: Object|Metric|Value|Option1|Option2|Option3|Option4|Option5
##################################################################
sub format_output_line
{
    my $r = $_[0];
    return $r->{OBJECT} . "|"
         . $r->{NUMBER}  . "|"
         . $r->{VALUE}   . "|"
         . ( $r->{OPTION1} // "None" ) . "|"
         . ( $r->{OPTION2} // "None" ) . "|"
         . ( $r->{OPTION3} // "None" ) . "|"
         . ( $r->{OPTION4} // "None" ) . "|"
         . ( $r->{OPTION5} // "None" ) . "\n";
}

##################################################################
# MAIN
##################################################################

my $grid = find_grid_config();
unless ( defined $grid )
{
    # No Grid / CRS home found — emit the section header but no data
    # so Checkmk does not go stale.
    print "<<<oracle_rac_services:sep(124)>>>\n";
    exit 0;
}

# Set environment so Oracle tools produce English output.
$ENV{ORACLE_SID}          = $grid->{SID};
$ENV{ORACLE_HOME}         = $grid->{ORAHOME};
$ENV{GRID_HOME}           = $grid->{ORAHOME};
$ENV{LD_LIBRARY_PATH}     = $grid->{ORAHOME} . "/lib";
$ENV{LIBPATH}             = $grid->{ORAHOME} . "/lib";    # AIX
$ENV{SRVM_PROPERTY_DEFS}  = "-Duser.language=en -Duser.country=US";
$ENV{NLS_LANG}            = "AMERICAN_AMERICA";
if ( is_windows() )
{
    $ENV{PATH} = make_ospath( $grid->{ORAHOME} . "\\bin" ) . ";" . $ENV{PATH};
}
else
{
    $ENV{PATH} = $grid->{ORAHOME} . "/bin:" . $ENV{PATH};
}

print "<<<oracle_rac_services:sep(124)>>>\n";

my @results = (
    metric5000($grid),
    metric5010($grid),
    metric5015($grid),
    metric5020($grid),
    metric5030($grid),
);

for my $r (@results)
{
    print format_output_line($r);
}
