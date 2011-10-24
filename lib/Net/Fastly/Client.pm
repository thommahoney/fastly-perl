package Net::Fastly::Client;

use strict;
use warnings;
use JSON;

=head1 NAME

Net::Fastly::Client - communicate with the Fastly HTTP API

=head1 SYNOPSIS


=head1 METHODS

=cut


=head2 new <opt[s]>

Create a new Fastly user agent. Options are

=over 4

=item user 

=item password

=item api_key

=back

=cut
sub new {
    my $class = shift;
    my %opts  = @_;
    my $self  = bless \%opts, $class;
    
    my $base  = $opts{base_url}  ||= "api.fastly.com";
    my $port  = $opts{base_port} ||= 80;
    $self->{_ua} = Net::Fastly::Client::UserAgent->new($base, $port);
    
    return $self unless $self->fully_authed;

    # If we're fully authed (i.e username and password ) then we need to log in
    my $res = $self->_ua->_post('/login', {}, user => $self->{user}, password => $self->{password});
    die "Unauthorized" unless $res->is_success;
    my $content = decode_json($res->decoded_content);    
    $self->{_cookie} = $res->header('set-cookie');
    return wantarray ? ($self, $content->{user}, $content->{customer}) : $self;
}

sub _ua { shift->{_ua} }

=head2 authed

Whether or not we're authed at all by either username & password or API key

=cut
sub authed {   
    my $self = shift;
    defined $self->{api_key} || $self->fully_authed;
}

=head2 fully_authed

Whether or not we're fully (username and password) authed

=cut
sub fully_authed {
    my $self = shift;
    defined $self->{user} && defined $self->{password};
}

sub _get {
    my $self = shift;
    my $path = shift;
    my %opts = @_;
    my $res  = $self->_ua->_get($path, $self->_headers, %opts);
    return undef if 404 == $res->code;
    my $content = decode_json($res->decoded_content);
    _raise_error($content) unless $res->is_success;
    return $content;
}

sub _post {
    my $self   = shift;
    my $path   = shift;
    my %params = @_;
    
    my $res    = $self->_ua->_post($path, $self->_headers, %params);
    my $content = decode_json($res->decoded_content);
    _raise_error($content) unless $res->is_success;
    return $content;
}

sub _put {
    my $self   = shift;
    my $path   = shift;
    my %params = @_;
    
    my $res    = $self->_ua->_put($path, $self->_headers, %params);
    my $content = decode_json($res->decoded_content);
    _raise_error($content) unless $res->is_success;
    return $content;
}

sub _delete {
    my $self = shift;
    my $path = shift;
    
    my $res  = $self->_ua->_delete($path, $self->_headers);
    return $res->is_success;
}

sub _headers {
    my $self   = shift;
    my $params = $self->fully_authed ? { 'Cookie' => $self->{_cookie} } : { 'X-Fastly-Key' => $self->{api_key} };
    $params->{'Content-Accept'} =  'application/json';
    return $params;
}

sub _raise_error {
    my $content = shift;
    die "".$content->{msg}."\n";
}


package Net::Fastly::Client::UserAgent;

use strict;
use URI;
use LWP::UserAgent;
use HTTP::Request::Common qw(GET HEAD PUT POST DELETE);

sub new {
    my $class = shift;
    my $base  = shift;
    my $port  = shift;
    return bless { _base => $base, _port => $port, _ua => Net::Fastly::UA->new }, $class;
}

sub _ua { shift->{_ua} }

sub _get {
    my $self    = shift;
    my $path    = shift;
    my $headers = shift;
    my %params  = @_;
    my $url     = $self->_make_url($path, %params);
    return $self->_ua->request(GET $url, %$headers); 
}

sub _post {
    my $self    = shift;
    my $path    = shift;
    my $headers = shift;
    my %params  = @_;
    my $url     = $self->_make_url($path);
    return $self->_ua->request(POST $url, [_make_params(%params)], %$headers);   
}

sub _put {
    my $self    = shift;
    my $path    = shift;
    my $headers = shift;
    my %params  = @_;
    my $url     = $self->_make_url($path, %params);
    return $self->_ua->request(PUT $url, %$headers, Content => ""); 
}

sub _delete {
    my $self    = shift;
    my $path    = shift;
    my $headers = shift;
    my %params  = @_;
    my $url     = $self->_make_url($path, %params);
    return $self->_ua->request(DELETE $url, %$headers); 
}

sub _make_url {
    my $self   = shift;
    my $base   = $self->{_base};
    my $port   = $self->{_port};
    my $path   = shift;
    my %params = @_;

    $base =~ s!^(https?:)//!!;
    my $prot = $1 || "https:";

    my $url = URI->new($prot);
    $url->host($base);
    $url->port($port) if $port != 80;
    $url->path($path);
    $url->query_form(_make_params(%params)) if keys %params;
    return $url;
}

sub _make_params {
    my %in = @_;
    my %out;
    
    foreach my $key (keys %in) {
        my $value = $in{$key};
        unless (ref($value) eq 'HASH') {
           $out{$key} = $value;
           next; 
        }
        foreach my $sub_key (keys %$value) {
            $out{$key."[".$sub_key."]"} = $value->{$sub_key};
        }
    }
    return %out;
}

package Net::Fastly::UA;

use base qw(LWP::UserAgent);
our $DEBUG=1;

sub request {
    my $self = shift;
    my $req  = shift;
    my $res  = $self->SUPER::request($req);
    if ($DEBUG) {
        print $req->as_string."\n------------------------\n\n";
        print $res->as_string."\n------------------------\n\n\n\n\n";
    }
    return $res;
}
1;