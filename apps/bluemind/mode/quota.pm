#
# Copyright 2017 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package apps::bluemind::mode::quota;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::http;
use JSON;
use Data::Dumper;


sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;


    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "hostname:s"              => { name => 'hostname' },
                                  "port:s"                  => { name => 'port', default => 443 },
                                  "proto:s"                 => { name => 'proto', default => 'https' },
                                  "credentials"             => { name => 'credentials' },
                                  "username:s"              => { name => 'username' },
                                  "password:s"              => { name => 'password' },
                                  "domainUid:s"             => { name => 'domainUid' },
                                  "warning:s"               => { name => 'warning', default => 80 },
                                  "critical:s"              => { name => 'critical', default => 90 },
                                });

    $self->{http} = centreon::plugins::http->new(output => $self->{output});

    return $self;
}


sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if ((!defined($self->{option_results}->{username}) || !defined($self->{option_results}->{password})))
    {
        $self->{output}->add_option_msg(short_msg => "You need to set --username= and --password= option");
        $self->{output}->option_exit();
    }

    if (!defined($self->{option_results}->{domainUid}))
    {
        $self->{output}->add_option_msg(short_msg => "Please set the --domainUid option");
        $self->{output}->option_exit();
    }


    $self->{http}->set_options(%{$self->{option_results}});

}

sub run {
    my ($self, %options) = @_;


    $self->{http}->add_header(key => 'Content-Type', value => 'application/json');
    $self->{http}->add_header(key => 'Accept', value => 'application/json');

    my $password='"'.$self->{option_results}->{password}.'"';

    my $url_path='/api/auth/login?login='.$self->{option_results}->{username};

    my $jsoncontent = $self->{http}->request(full_url => $self->{option_results}->{proto}
                                            . '://'
                                            . $self->{option_results}->{hostname}
                                            . $url_path,
                                            method => 'POST',
                                            query_form_post =>$password);



    my $json = JSON->new;

    my $webcontent = $json->decode($jsoncontent);


    $self->{http}->add_header(key => 'X-BM-ApiKey', value => $webcontent->{'authKey'});

    my $jsoncontent2 = $self->{http}->request(full_url => $self->{option_results}->{proto}
                                               . '://'
                                               . $self->{option_results}->{hostname}
                                               . '/api/mailboxes/'
                                               . $self->{option_results}->{domainUid}
                                               . '/_list',
                                               method => 'GET');


    my $json2 = JSON->new;

    my $webcontent2 = $json2->decode($jsoncontent2);


    my $jsoncontent3;


    my %hash;

    my $key_mail;


    my $short_msg="";
    my $long_msg;
    my $severity='OK';

    foreach my $item(@$webcontent2)
    {

      if (defined $item->{'value'}{'emails'}[0] && defined $item->{'value'}{'quota'})
      {

         $key_mail=$item->{'value'}{'emails'}[0]{'address'};

         $jsoncontent3 = $self->{http}->request(full_url => $self->{option_results}->{proto}
                                                . '://'
                                                . $self->{option_results}->{hostname}
                                                . '/api/mailboxes/'
                                                . $self->{option_results}->{domainUid}
                                                . '/'
                                                . $item->{'uid'}
                                                . '/_quota',
                                                method => 'GET');


         $hash{$key_mail}=$json2->decode($jsoncontent3);
         $hash{$key_mail}->{'percentage'} = $hash{$key_mail}->{'used'} * 100 / $hash{$key_mail}->{'quota'};

          if ($hash{$key_mail}->{'percentage'}>=$self->{option_results}->{critical})
          {

                $severity='Critical';
                $short_msg=$short_msg .' '. $key_mail;

          }
          else
          {
            if ($hash{$key_mail}->{'percentage'}>=$self->{option_results}->{warning})
            {

             if ($severity ne 'Critical')
             {
                $severity='Warning';
                $short_msg=$key_mail.' '.'mailbox';
             }
           }
          }

      if ($severity eq 'OK')
      {
            $short_msg='All mailboxes are ok';
      }

        $self->{output}->perfdata_add(label    => 'quota_used_'.$key_mail,
                                      value    => sprintf("%.2f",$hash{$key_mail}->{'percentage'}),
                                      unit     => '%');
     }

  }

  $self->{output}->output_add(severity  => $severity,
                               short_msg  =>  $short_msg,
                               long_msg => $long_msg,
                               separator => "\n");


  $self->{output}->display();
  $self->{output}->exit();

 }


1;

__END__

=head1 MODE

Check quota from Bluemind server.

=over 6

=item B<--hostname>

IP Addr/FQDN of the Bluemind host.

=item B<--port>

Port used by Bluemind API. (Default: 443)

=item B<--proto>

Specify http or https protocol. (Default: https)

=item B<--domainUid>

Specify your Bluemind domain name.

=item B<--username>

Specify username for API authentification.

=item B<--password>

Specify password for API authentification.

=item B<--warning>

Threshold warning. (Default : 80)

=item B<--critical>

Threshold critical. (Default : 90)

=back

=cut

