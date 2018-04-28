#!/usr/bin/perl -w 

# @filename           :  GetCustomsParameters.pl
# @author             :  Copyright (C) Church.Zhong
# @date               :  Thu Apr 26 15:58:10 HKT 2018
# @function           :  
# @see                :  http://query.customs.gov.cn/HYW2007DataQuery/Cscx/CscxMsList.aspx
# @require            :  


# require here
#require v5.6.1;


# use standard library/use warnings
use strict;
use warnings;
use utf8;
# work well on v5.24.2
use HTML::TreeBuilder;

sub usage
{
	print "usage:\n";
	print "$0 V1.0.0 \n";
	print "\n";
}


################################################################################
### global vars
################################################################################
sub getCurrentTime
{
	my $time = time();
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);

	$sec  = ($sec<10)?"0$sec":$sec;
	$min  = ($min<10)?"0$min":$min;
	$hour = ($hour<10)?"0$hour":$hour;
	$mday = ($mday<10)?"0$mday":$mday;
	$mon  = ($mon<9)?"0".($mon+1):$mon;
	$year+=1900;
	my $weekday = ('Sun','Mon','Tue','Wed','Thu','Fri','Sat')[$wday];
	return { 'second' => $sec,
			'minute' => $min,
			'hour'   => $hour,
			'day'    => $mday,
			'month'  => $mon,
			'year'   => $year,
			'weekNo' => $wday,
			'wday'   => $weekday,
			'yday'   => $yday,
			'date'   => "$year$mon$mday"
			};
}

my $OPERATING_SYSTEM = 0;
my $USER_NAME = 0;
my $WORK_DIR = 0;
my $OS_DATE = 0;
use Cwd;

# http://perldoc.perl.org/perlport.html#PLATFORMS
my $zdebug = 0;
use Config;
sub init_global_vars
{
	# MSWin32/linux
	$OPERATING_SYSTEM = $Config{'osname'};
	print "$OPERATING_SYSTEM\n" if $zdebug;

	my $user=qx{whoami};
	$USER_NAME=(split(/\\/, $user))[-1];
	chomp($USER_NAME);
	print "$USER_NAME\n" if $zdebug;


	#@deprecated
	#$WORK_DIR=`pwd`;
	$WORK_DIR=cwd();
	chomp($WORK_DIR);
	print "$WORK_DIR\n" if $zdebug;


	#@deprecated
	#$OS_DATE=`date --date= +%Y%m%d`;
	my $date = &getCurrentTime();
	$OS_DATE = $date->{date};
	chomp($OS_DATE);
	print "$OS_DATE\n" if $zdebug;


	print "\n"x3 if $zdebug;
	return (0);
}


################################################################################
### helper
################################################################################
sub open_filehandle_for_write
{
	my $filename = $_[0];
	my $overWriteFilename = $filename;
	local *FH;

	open (FH, '>', $overWriteFilename) || die "Could not open $filename";

	return *FH;
}

sub open_filehandle_for_read
{
	my $filename = $_[0];
	local *FH;

	open (FH, '<', $filename) || die "Could not open $filename";

	return *FH;
}

sub ltrim { my $s = shift; $s =~ s/^\s+//;       return $s };
sub rtrim { my $s = shift; $s =~ s/\s+$//;       return $s };
sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };


use File::Spec;
sub get_abs_path
{
	# best code, get file true path.
	my $path_curf = File::Spec->rel2abs(__FILE__);
	#print ("file in PATH = ",$path_curf,"\n");
	my ($vol, $dirs, $file) = File::Spec->splitpath($path_curf);
	#print ("file in Dir = ", $dirs,"\n");

	return $dirs;
}

sub saveHtmlcontentFile
{
	my $fileName = $_[0];
	open my $fileRef, ">:encoding(UTF-8)", $fileName or die "Write $fileName failed!";
	print $fileRef $_[1];
	close($fileRef);
}


################################################################################
### http
################################################################################

use LWP;
use LWP::Simple;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Headers;
use HTTP::Response;
use Encode;
use URI::Escape;
use URI::URL;
my $ua = LWP::UserAgent->new;


my %CscxMsList = ();
use Encode qw/encode/;

my $eventTarget;
my $eventArgument;
my $__VIEWSTATE;
my $__EVENTVALIDATION;
my $hiddenTableID;
my $DeluxePager1_txtGoto;
my $DeluxePager1_txtPageCount;


sub WriteCsv
{
	my $tree = shift;
	my $csvFileRef = shift;
	my $gotThead = shift;
	my $record = 0;

	my $thead_saved = 0;
	my $thead_size = 0;
	my @thead = ();
	my @tbody = ();
	foreach my $tag ( $tree->find_by_attribute('align', 'center') )
	{
		if ((0 eq $thead_saved) and (!$tag->parent->find_by_attribute('class', 'grid-head')))
		{
			next;
		}

		my $tag_name = $tag->tag();
		my $text = $tag->as_text;
		if ('th' eq $tag_name)
		{
			if (0 == $thead_saved)
			{
				$thead_saved = 1;
			}
			push @thead, $text;
		}
		elsif ('td' eq $tag_name)
		{
			if (1 eq $thead_saved)
			{
				$thead_saved = 2;
				$thead_size = @thead;
				print $csvFileRef join(",", @thead) . "\n" if (0 eq $gotThead);
				#print encode("gbk", join(",", @thead) . "\n");
			}

			push @tbody, $text;
			if ($thead_size eq @tbody)
			{
				print $csvFileRef join(",", @tbody) . "\n";
				#print encode("gbk", join(",", @tbody) . "\n");
				@tbody = ();
				$record++;
			}
		}
		else
		{
			print "who are you? \r\n";
		}
	}
	return $record;
}

sub getCscxListViewData
{
	my $webpage = shift;
	my $csvFileRef = shift;# close file by caller!
	my $gotThead = shift;

	my $tree = new HTML::TreeBuilder();
	$tree->parse( $webpage );

	my ($totalRecord, $pageSize, $pageNumber, $totalPage, $record) = (0, 0, 0, 0, 0);
	my $DeluxePageRow = $tree->find_by_attribute('id', 'DeluxePager1_pagerRow');
	if (!$DeluxePageRow)
	{
		print "Error: not find id=DeluxePager1_pagerRow tag!\r\n";
		goto DELETE_TREE;
	}
	my $td = $DeluxePageRow->find_by_attribute('style', 'text-align:left;');
	if (!$td)
	{
		print "Error: not find id=DeluxePager1_pagerRow tag!\r\n";
		goto DELETE_TREE;
	}

	my @span = $td->find_by_tag_name('span');
	if (@span eq 4)
	{
		$totalRecord = trim($span[0]->as_text);
		$pageSize = trim($span[1]->as_text);
		$pageNumber = trim($span[2]->as_text);
		$totalPage = trim($span[3]->as_text);
		print "  totalRecord=$totalRecord, pageSize=$pageSize, pageNumber=$pageNumber, totalPage=$totalPage  \r\n";
	}
	else
	{
		print "Error: not find 4 span tag!\r\n";
		goto DELETE_TREE;
	}

	my $a = $tree->find_by_attribute('id', 'DeluxePager1_lbtnNext');
	if (!$a)
	{
		print "Error: not find id=DeluxePager1_lbtnNext tag!\r\n";
		goto WRITE_CSV;
	}
	my $href = $a->attr('href');
	if (!$href)
	{
		print "Yeah! one page!\r\n";
		goto WRITE_CSV;
	}

	if ($href =~ m/javascript:__doPostBack\(\'(.*)\',\'(.*)\'\)/)
	{
		print "href=$href \r\n";
		$eventTarget = $1;
		$eventArgument = $2;
	}
	else
	{
		print "Error: href=$href, match failed! \r\n";
		goto WRITE_CSV;
	}


	$__VIEWSTATE = $tree->find_by_attribute('id', '__VIEWSTATE')->attr('value');
	$__EVENTVALIDATION = $tree->find_by_attribute('id', '__EVENTVALIDATION')->attr('value');
	$hiddenTableID = $tree->find_by_attribute('id', 'hiddenTableID')->attr('value');
	$DeluxePager1_txtGoto = $tree->find_by_attribute('id', 'DeluxePager1_txtGoto')->attr('value');
	$DeluxePager1_txtPageCount = $tree->find_by_attribute('id', 'DeluxePager1_txtPageCount')->attr('value');
	#print "got eventTarget=$eventTarget, eventArgument=$eventArgument, __VIEWSTATE=$__VIEWSTATE \r\n" if ($href);
	print "got DeluxePager1_txtGoto=$DeluxePager1_txtGoto, DeluxePager1_txtPageCount=$DeluxePager1_txtPageCount \r\n";


WRITE_CSV:
	$record = WriteCsv($tree, $csvFileRef, $gotThead);
DELETE_TREE:
	$tree->delete;
	return {
			'totalRecord'=>$totalRecord,
			'pageSize'=>$pageSize,
			'pageNumber'=>$pageNumber,
			'totalPage'=>$totalPage,
			'record'=>$record
			};
}

sub getEachList
{
	srand();
	my $path = get_abs_path(). $OS_DATE . '_' . int(rand(1024)) . '_data/';
	mkdir $path;


	my $prefix = 'http://query.customs.gov.cn/HYW2007DataQuery/Cscx/';
	foreach my $key ( sort keys %CscxMsList )
	{
		my $gotThead = 0;# Here, Set $gotThead=False;
		#$totalPage = ($totalRecord + $pageSize -1) / $pageSize;
		my ($totalRecord, $pageSize, $pageNumber, $totalPage, $record) = (0, 0, 0, 0, 0);

		my $tableName = "";
		if ($CscxMsList{$key} =~ m/tableName=(.*)$/)
		{
			$tableName=$1;
		}
		print "  tableName=$tableName \r\n";

		my $url = $prefix . $CscxMsList{$key};
		print "  process url=$url \r\n";
		my $response = $ua->get( $url );
		die "get $url failed!\r\n" if(!$response->is_success);

		my $webpage = decode_utf8( $response->content );

		my $csvFileName = encode("gbk", $path . $key . '.csv');
		open my $csvFileRef, ">:encoding(UTF-8)", $csvFileName or die "open $csvFileName failed!";
		my $total = &getCscxListViewData($webpage, $csvFileRef, $gotThead);
		$totalRecord = $total->{'totalRecord'};
		$pageSize = $total->{'pageSize'};
		$pageNumber = $total->{'pageNumber'};
		$totalRecord = $total->{'totalRecord'};
		$totalPage = $total->{'totalPage'};
		$record += $total->{'record'};
		print "  totalRecord=$totalRecord, totalPage=$totalPage, record=$record  \r\n";
		saveHtmlcontentFile($path . $tableName . '_' . $totalPage . '_debug.html', $webpage );

		for ($totalPage--; $totalPage>0; $totalPage--)
		{
			$gotThead = 1;# Here, Set $gotThead=True;
			print "leftPage=$totalPage\r\n";

			my %form_hash = (
				'__EVENTTARGET' => $eventTarget,
				'__EVENTARGUMENT' => $eventArgument,
				'__VIEWSTATE' => $__VIEWSTATE,
				'__EVENTVALIDATION' =>$__EVENTVALIDATION,
				'hiddenTableID' => $hiddenTableID,
				'DeluxePager1$txtGoto' => $DeluxePager1_txtGoto,
				'DeluxePager1$txtPageCount' => $DeluxePager1_txtPageCount
			);

			my $postTry = 0;
			while (!$postTry)
			{
				$response=$ua->post($url,
						\%form_hash,
						'Referer' => $url,
						'Content-Type' => 'application/x-www-form-urlencoded');
				$postTry = $response->is_success;
				if ($response->is_success)
				{
					print "  post $url OK!  \r\n";
					$webpage = decode_utf8( $response->content );
					saveHtmlcontentFile($path . $tableName . '_' . $totalPage . '_debug.html', $webpage );
					$total = &getCscxListViewData($webpage, $csvFileRef, $gotThead);
					$record += $total->{'record'};
					if ($record eq $totalRecord)
					{
						print "  Finished: record=$record, totalRecord=$totalRecord  \r\n";
					}
				}
				else
				{
					print "  post $url failed!  \r\n" ;
					sleep(36);
				}
			}
			#last;
			sleep(16);
		}
		close($csvFileRef);
		sleep(16);
	}
}

sub getCscxMsListHtml
{
	my $url = 'http://query.customs.gov.cn/HYW2007DataQuery/Cscx/CscxMsList.aspx';
	my $response = $ua->get( $url );
	die "get $url failed!\r\n" if(!$response->is_success);

	my $tree = new HTML::TreeBuilder();

	$tree->parse( decode_utf8($response->content) );
	my $id = $tree->find_by_attribute('id', 'MSDataList');
	if (!$id)
	{
		$tree->delete;
		die "Error: not find id=MSDataList tag!\r\n";
	}

	my ($href, $title) = ("", "");
	foreach my $a ( $id->find_by_tag_name('a') )
	{
		$href = $a->attr('href');
		$title = $a->as_text;
		$CscxMsList{$title} = $href;
		#print encode("gbk", $title), " => ", $href, "\n";
	}
	my $length = keys %CscxMsList;
	print "\r\n  CscxMsList size=$length  \r\n" if ($length);

	$tree->delete;
}


################################################################################
### MAIN
################################################################################


	#监管方式代码表
	#征免性质代码表
	#国别(地区)代码表
	#国内地区代码表
	#关区代码表
	#币制代码表
	#计量单位代码表
	#企业性质代码表
	#地区性质代码表
	#成交方式代码表
	#用途代码表
	#结汇方式代码表
	#运输方式代码表
	#征减免税方式代码表
	#监管证件代码表


#usage();
# sanity check
init_global_vars();

getCscxMsListHtml();
getEachList();

exit 0;


################################################################################
### MAIN
################################################################################
