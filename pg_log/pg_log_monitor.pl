#!/usr/bin/perl

#Performs initial script configuration. Must be executed within BEGIN
#in order to dynamically set "use lib" value. 
BEGIN{

    @MAILER_RELAY_IPS = ('127.0.0.1');
    $SCRIPT_DIR='/home/postgres/bin/pg_log';
    $LIB_DIRECTORY='';
    $SERVER_HOSTNAME='';
    $TO_ADDRESS='';
    $FROM_ADDRESS='';
    $ERROR_LINE_FLAGS='';
    $day = (localtime)[3];
    $month = (localtime)[4];
    $year = (localtime)[5];
    $month += 1; $year += 1900;

    $CURRENT_DATE = sprintf("%02d/%02d/%04d", $month, $day, $year);
    
    open(SC, '<', "$SCRIPT_DIR/settings.conf");
        my @settings = <SC>;
    close(SC);
    
    foreach my $line (@settings){
        chomp($line);
        my @setting = split(':', $line);       
        if($setting[0] =~ m/^lib_directory/i){
            $LIB_DIRECTORY = $setting[1];
        }
        elsif($setting[0] =~ m/^server_hostname/){
            $SERVER_HOSTNAME = $setting[1];
            chomp($SERVER_HOSTNAME);
        }elsif($setting[0] =~ m/^from_address/){
            $FROM_ADDRESS = $setting[1];
            chomp($FROM_ADDRESS);
        }elsif($setting[0] =~ m/^to_address/){
            $TO_ADDRESS = $setting[1];
            chomp($TO_ADDRESS);
        }elsif($setting[0] =~ m/^error_flags/){
            chomp($setting[1]);
            my @error_flags = split(',', $setting[1]);
            $ERROR_LINE_FLAGS = join('|', @error_flags);
        }
    }
    
}

#Package/Class Includes
use lib $LIB_DIRECTORY;
use Time::Local;
use Switch;
use MIME::Lite;
use Socket;
use Sys::Hostname;
use Data::Dumper;

#Command Line Options
my $directory='';
my $timespan=1;
my $static_ignore=0;
my $dynamic_ignore=0;
my $start_with_yesterday=0;
my $cron=0;

#Grab CL Arguments
for(my $x = 0; $x <= $#ARGV; $x++){
    switch($ARGV[$x]){          
        case '-h' { display_help_text(); exit; }

        case '-t' { $timespan=$ARGV[$x + 1]; }
        
        case '-d' { $directory=$ARGV[$x + 1]; }
	      
        case '-i' { $static_ignore = 1; }
	      
        case '-ix' { $dynamic_ignore = 1; }
	      
        case '-c' { $cron = 1; } 
        
        case '-y' { $start_with_yesterday = 1; }
	 }
}

#Check for required params
die "You must pass in a directory with the -d option." unless $directory;
		
my @logfile_1_errors;
my @logfile_2_errors;
my @static_ignore_messages;
my @dynamic_ignore_regex;
my @unique_error_msgs;
my @seen_error_msgs;

#Load .dat configurations
@static_ignore_messages = load_static_ignore();
@dynamic_ignore_regex = load_dynamic_ignore();


  #Main Application Logic

   #Populate array of all logfile path names, sorted in descending order
    opendir(FH, $directory);
       my @file_list = grep(/^postgresql.*\.log$/, readdir(FH));
    closedir(FH);
    
    @file_list = sort {$b cmp $a} @file_list;

   #Iterate through directory tree until timespan reached
    for($count=0; $count < scalar(@file_list); $count++){   
     
      if($start_with_yesterday){
         $start_with_yesterday=0;
         next;
      }
     
      $logfile_1_path = $directory."/".$file_list[$count];
      $logfile_2_path = $directory."/".$file_list[$count + 1];
    
      @logfile_1_errors = load_errors($logfile_1_path);
      @logfile_2_errors = load_errors($logfile_2_path);
    
      if($static_ignore){
        @logfile_1_errors = remove_static_ignore(@logfile_1_errors);
        @logfile_2_errors = remove_static_ignore(@logfile_2_errors);    
      }
    
      if($dynamic_ignore){
        @logfile_1_errors = remove_dynamic_ignore(@logfile_1_errors);
        @logfile_2_errors = remove_dynamic_ignore(@logfile_2_errors);        
      }
  
      my $new_ref; my $recurring_ref;
      ($new_ref, $recurring_ref) = compare_logfiles( \@logfile_1_errors, \@logfile_2_errors);
      @new = @$new_ref; 
      @recurring = @$recurring_ref;
    
      @new = remove_duplicates(@new);
      @recurring = remove_duplicates(@recurring);
    
    
      #Assemble Report for display or e-mail
     
      my $report = generate_output();
     
      if($cron){
    
          print "Sending e-mail. . .\n";
          
            my $addr = gethostbyname($name);
                 
            my $success='';
            my $hostname = `hostname`;
            my $report_date='';
            ($report_date) = $logfile_1_path =~ m/(\d{4}-\d{2}-\d{2})\.log$/;
            my $subject = "Postgres database pg_log errors on $SERVER_HOSTNAME for $report_date";
            my $body = $report;
            chomp($hostname);
            foreach (@MAILER_RELAY_IPS){
                eval {
                    my $msg = new MIME::Lite(  Type => 'text/plain', 
                                                From => $FROM_ADDRESS, 
                                                To => $TO_ADDRESS,
                                                Data => $body,
                                                Subject => $subject
                    );

                     $msg->send('smtp',$_, Debug=>0);
                 };
                 if (!$@) {
                     $success = 1;
                     last;
                 }
             }
             if (!$success){
                     die "E-mail attempt failed for pg_log_monitor.pl.\n";
             }          
    
      } 
      else{        
        print "\nCompleted report for $report_date.\n";
        print "Action: [d]isplay error(s), [w]rite to file, or [s]kip: ";
        $choice = <STDIN>;
        chomp($choice);
             
            switch($choice){
                case 'd'  {
                   print $report;
                   print "\n\nPress enter to continue: ";
                   <STDIN>;
                }

                case 'w'  {
                    open(FH, '>>', 'new_pg_errors.txt');
                        print FH $report;
                    close(FH);
                    print "\nAppeneded to file new_pg_errors.txt.\n\n";
                    print "Press enter to continue: ";
                    <STDIN>;                    
                }
           }
     }   

     last unless ($count + 1) < $timespan;
    
    }#End main logic loop

###########################
#### Support Functions ####
###########################

sub load_errors(){

my $logpath = shift; 
my @lines;    
  
    open(FH, '<', "$logpath");

    while(my $line = <FH>){
       chomp($line);
       (my $placeholder, $error_message) = $line =~ m/($ERROR_LINE_FLAGS)\:\s*(.+)/;
       if($error_message){
            $error_message =~ s/^\s+//;
            $error_message =~ s/\s+$//;
            push(@lines, $error_message);
       }
    }

    close(FH);   
   
return @lines;

}

sub load_static_ignore{

my @ignore_messages;

    open(FH, '<', "$SCRIPT_DIR/static_ignore.dat");

        while(my $line = <FH>){
            chomp($line);
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;
            push(@ignore_messages, $line);    
        }
        
    close(FH);

return @ignore_messages;

}

sub load_dynamic_ignore{

my @ignore_regex; 

    open(FH, '<', "$SCRIPT_DIR/dynamic_ignore.dat");

        while(my $line = <FH>){
            chomp($line);
            $line =~ s/^\s+//;
            $line =~ s/\s+$//;
            push(@ignore_regex, $line);    
        }
        
    close(FH);

    foreach $line (@ignore_regex){
       $line = replace_special_chars($line);
       $line =~ s/::DYN::/\.\+/g;
       $line = '^'.$line.'$';
    }
    
return @ignore_regex;

}


sub compare_logfiles(){

$ref_1 = $_[0];
$ref_2 = $_[1];

my @logfile_1 = @$ref_1;
my @logfile_2 = @$ref_2;

my @new_errors;
my @recurring_errors; 
my $match=0;

foreach my $line1 (@logfile_1){

    foreach my $line2 (@logfile_2){
       $match = 1 unless ($line1 ne $line2);
    }
    
    if($match){
      push(@recurring_errors, $line1);
    }
    else{
      push(@new_errors, $line1);
    }
    
    $match = 0;
    
}

return (\@new_errors, \@recurring_errors);
   
}

sub remove_static_ignore{

my @stat = @_;
my @valid_lines; 

    my $static_error = 0;
	foreach my $line_message (@stat){
        foreach my $ignore_error (@static_ignore_messages){
	        if($ignore_error eq $line_message){
                $static_error = 1;
            }
        }
        push(@valid_lines, $line_message) unless $static_error;
        $static_error = 0;
    }

return @valid_lines;

}

sub remove_dynamic_ignore{

my @lines = @_;
my @valid_lines; 

    my $found_dyn_error = 0;
	foreach my $line_message (@lines){
        foreach my $ignore_regex (@dynamic_ignore_regex){
	        if($line_message =~ m/$ignore_regex/){
                $found_dyn_error = 1;
            }
        }
        push(@valid_lines, $line_message) unless $found_dyn_error;
        $found_dyn_error = 0;
    }

return @valid_lines;

}

sub remove_duplicates{

my @lines = @_;
my %hash   = map { $_ => 1 } @lines;
my @unique = keys %hash;
    
return @unique; 

}

sub generate_output{

    ($report_date) = $logfile_1_path =~ m/(\d{4}-\d{2}-\d{2})\.log$/;
    my @full_new_lines;
    my @full_recurring_lines;

    if(scalar(@new) > 0){
        $output .= "\nNew Errors:\n";
        $output .= "--------------------------------------------------\n";    
       
        foreach $error (@new){
        
            $error = replace_special_chars($error);
        
            open(FH, '<', $logfile_1_path);
            my $is_duplicate=0;
            while(my $rawline = <FH>){
            $is_duplicate=0;
            chomp($rawline);
            if($rawline =~ $error){
               foreach $full_line (@full_new_lines){
                   if($full_line =~ $error){
                      $is_duplicate=1;
                   }
               }
               push(@full_new_lines, $rawline) unless $is_duplicate == 1;
            }
        }
           
           close(FH);

        }
      
        @full_new_lines = sort @full_new_lines;  
        my $line_count = 0;
        foreach my $full_line (@full_new_lines){
            $line_count++;
            $output .= "[".$line_count."]\n";
            $output .= $full_line."\n";
            open(FH, '<', $logfile_1_path);
                while($line = <FH>){
                    chomp($line);
                    if($line !~ m/FATAL\:/){
                    if($line eq $full_line){
                        my $start_byte_count = tell FH;

                        for(my $x = 1; $x <= 2; $x++){
                           my $context_line = <FH>;
                           if($context_line =~ m/$ERROR_LINE_FLAGS\:/){
                              break; 
                           }
                           if($context_line =~ m/STATEMENT\:|HINT\:|DETAIL\:|CONTEXT\:|LOG\:/){
                              $output .= $context_line;
                           }
                        }
                        

                        my $end_byte_count = tell FH;
                        my $rewind_byte_count = -1 * ($end_byte_count - $start_byte_count);
                        seek FH, $rewind_byte_count, 1;
                    }
                    }
                }
            close(FH);
        }
        
        
    }

    if(scalar(@recurring) > 0){
        $output .= "\nRecurring Errors:\n";    
        $output .= "--------------------------------------------------\n";
    
        foreach $error (@recurring){

           open(FH, '<', $logfile_1_path);

            while(my $rawline = <FH>){
            my $is_duplicate = 0;
            chomp($rawline);
            if($rawline =~ $error){
                foreach $full_recurring (@full_recurring_lines){
                     if($full_recurring =~ $error){
                       $is_duplicate = 1; 
                     }
                }
                push(@full_recurring_lines, $rawline) unless $is_duplicate == 1;
            }
         }
           
         close(FH);

        }
       
        @full_recurring_lines = sort @full_recurring_lines; 
        $line_count = 0;
        foreach my $full_line (@full_recurring_lines){
            $line_count++;
            $output .= "[".$line_count."]\n";
            $output .= $full_line."\n";
            open(FH, '<', $logfile_1_path);
                while($line = <FH>){
                    chomp($line);
                    if($line eq $full_line){
                        my $start_byte_count = tell FH;

                        for(my $x = 1; $x <= 2; $x++){
                           my $context_line = <FH>;
                           if($context_line =~ m/$ERROR_LINE_FLAGS\:/){
                              break; 
                           } 
                           if($context_line =~ m/STATEMENT\:|HINT\:|DETAIL\:|CONTEXT\:/){
                              $output .= $context_line;
                           }
                        }

                        my $end_byte_count = tell FH; 
                        my $rewind_byte_count = -1 * ($end_byte_count - $start_byte_count);
                        seek FH, $rewind_byte_count, 1; 
                    }
                }
            close(FH);
        }        
        
    }
    
      my $output_heading  =  "\nReport For Date: $report_date\nTotal New Unique Errors Found: ". @full_new_lines;
          if($static_ignore && $dynamic_ignore){
              $output_heading .= " (Minus Static & Dynamic Ignores)\n";
          }
          elsif($static_ignore){
             $output_heading .= " (Minus Static Ignores)\n";
          }
          elsif($dynamic_ignore){
             $output_heading .= " (Minus Dynamic Ignores)\n";
          }
          else{
             $output_heading .= "\n";
          }     
      $output_heading .=  "Total Recurring Unique Errors: ". @full_recurring_lines;
       
         if($static_ignore && $dynamic_ignore){
             $output_heading .= " (Minus Static & Dynamic Ignores)\n";
         }
         elsif($static_ignore){
             $output_heading .= " (Minus Static Ignores)\n";
         }
         elsif($dynamic_ignore){
             $output_heading .= " (Minus Dynamic Ignores)\n";
         }
         else{
             $output_heading .= "\n";
         }        
    
    $output = $output_heading.$output; 
    
    return $output; 
    
}

sub replace_special_chars(){

my $data_string = shift; 

$data_string =~ s/([\$\.\"\'\(\)\|\*\[\]])/\\$1/g;

return $data_string;

}

sub display_settings(){
    print "Initial Settings:\n";
    print "-------------------------\n";
    print "Lib Directory: $LIB_DIRECTORY\n";
    print "Script Directory: $SCRIPT_DIR\n";
    print "Server hostname: $SERVER_HOSTNAME\n";
    print "To Address: $TO_ADDRESS\n";
    print "From Address: $FROM_ADDRESS\n";
    print "Current Date: $CURRENT_DATE\n";

    print "\nCommand Line Arguments:\n";
    print "-------------------------\n";
    print "Logfile Directory: $directory\n";
    print "Report Timespan: $timespan days\n";
    print "Static Ignore: $static_ignore\n";
    print "Dynamic Ignore: $dynamic_ignore\n";
    print "Cron Switch: $cron\n";
}

sub display_help_text(){
    print "Example Usage: pg_log_monitor.pl -d '/data/logs/pg_log' [option] [arg].\n\n";
    print "Required Options:\n";
    print "   -d: Accepts an absolute path to the log directory to be analyzed.\n";
    print "Optional Flags:\n";
    print "   -t: The timespan (in days) to analyze log files within. Default value is 2.\n";
    print "   -i: Static ignore. Ignores static error messages stored in 'static_ignore.dat'.\n";
    print "   -ix: Dynamic ignore. Ignores dynamic error message templates stored in 'dynamic_ignore.dat'.\n";
    print "   -c: Run script in cron mode. Bypasses need for manual entry and e-mails errors to DBA team.\n";
    print "   -h: Display help. Generates this message and exits script.\n";
    print "\n\n";   
}

sub dump_array(){

  my @array = @_; 
  
  foreach $line (@array){
  
     print $line."\n";
  
  }

}
