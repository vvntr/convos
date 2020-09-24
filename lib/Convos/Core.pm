package Convos::Core;
use Mojo::Base -base;

use Convos::Core::Backend;
use Convos::Core::Settings;
use Convos::Core::User;
use Convos::Util qw(DEBUG has_many);
use Mojo::File;
use Mojo::Log;
use Mojo::URL;
use Mojo::Util 'trim';
use Mojolicious::Plugins;

has backend  => sub { Convos::Core::Backend->new };
has base_url => sub { Mojo::URL->new };
has home     => sub { Mojo::File->new(split '/', $ENV{CONVOS_HOME}); };
has log      => sub { Mojo::Log->new };
has ready    => 0;

has settings => sub {
  my $self     = shift;
  my $settings = Convos::Core::Settings->new;
  Scalar::Util::weaken($settings->{core} = $self);
  return $settings;
};

sub connect {
  my ($self, $connection, $reason) = @_;
  my $host = $connection->url->host;

  $connection->state(queued => $reason || 'Connecting soon...');

  if ($host eq 'localhost') {
    $connection->connect;
  }
  elsif ($self->{connect_queue}{$host}) {
    push @{$self->{connect_queue}{$host}}, $connection;
    Scalar::Util::weaken($self->{connect_queue}{$host}[-1]);
  }
  else {
    $self->{connect_queue}{$host} = [];
    $connection->connect;
  }

  return $self;
}

sub connections_by_id {
  my ($self, $cid) = @_;

  return $self->users->map(sub {
    shift->connections->grep(sub { shift->id eq $cid });
  })->flatten;
}

sub get_user_by_uid {
  my ($self, $uid) = @_;
  return +(grep { $_->uid eq $uid } @{$self->users})[0];
}

sub new {
  my $self = shift->SUPER::new(@_);

  if ($self->{backend} and !ref $self->{backend}) {
    eval "require $self->{backend};1" or die $@;
    $self->{backend} = $self->{backend}->new(home => $self->home);
  }

  return $self;
}

sub remove_user_p {
  my ($self, $user) = @_;
  my @p = $user->connections->map(sub { $user->remove_connection_p($_) })->each;
  my $p = @p ? Mojo::Promise->all(@p) : Mojo::Promise->resolve;

  return $p->then(sub { $self->backend->delete_object_p($user) })
    ->then(sub { $self->remove_user($user->id); $user });
}

sub start {
  my $self = shift;
  return $self if !@_ and $self->{started}++;

  my ($first_user, $has_admin, $uid) = (undef, 0, 0);
  $self->backend->users_p->then(sub {
    my $users = shift;

    my (@p, @users);
    for (@$users) {
      my $user = $self->user($_);
      $first_user ||= $user;
      $has_admin++ if $user->role(has => 'admin');
      push @p,     $self->backend->connections_p($user);
      push @users, $user;
    }

    return Mojo::Promise->all(Mojo::Promise->resolve(\@users), @p);
  })->then(sub {
    my ($users, @connections_for_users) = map { $_->[0] } @_;

    for my $connections (@connections_for_users) {
      my $user = shift @$users;

      for (@$connections) {
        my $connection = $user->connection($_);
        $self->connect($connection)
          if !$ENV{CONVOS_SKIP_CONNECT} and $connection->wanted_state eq 'connected';
      }
    }

    # Upgrade the first registered user (back compat)
    $first_user->role(give => 'admin') if $first_user and !$has_admin;
    $self->ready(1);
  })->catch(sub {
    warn "start() FAILED $_[0]\n";
  });

  Scalar::Util::weaken($self);
  $self->{connect_tid}
    = Mojo::IOLoop->recurring($ENV{CONVOS_CONNECT_DELAY} || 4, sub { $self->_dequeue });

  return $self;
}

has_many users => 'Convos::Core::User' => sub {
  my ($self, $attrs) = @_;
  $attrs->{email} = trim lc $attrs->{email} || '';
  $attrs->{uid} ||= $self->n_users + 1;
  $attrs->{uid}++ while $self->get_user_by_uid($attrs->{uid});
  my $user = Convos::Core::User->new($attrs);
  die "Invalid email $user->{email}. Need to match /.\@./." unless $user->email =~ /.\@./;
  Scalar::Util::weaken($user->{core} = $self);
  return $user;
};

sub web_url {
  my $self = shift;
  my $url  = Mojo::URL->new(shift);

  $url->base($self->base_url->clone)->base->userinfo(undef);
  my $base_path = $url->base->path;
  unshift @{$url->path->parts}, @{$base_path->parts};
  $base_path->parts([])->trailing_slash(0);

  return $url;
}

sub _dequeue {
  my $self = shift;

  for my $host (keys %{$self->{connect_queue} || {}}) {
    next unless my $connection = shift @{$self->{connect_queue}{$host}};
    $connection->connect if $connection and $connection->wanted_state eq 'connected';
  }
}

sub DESTROY {
  my $self = shift;
  Mojo::IOLoop->remove($self->{connect_tid}) if $self->{connect_tid};
}

1;

=encoding utf8

=head1 NAME

Convos::Core - Convos backend

=head1 DESCRIPTION

L<Convos::Core> is the heart of the Convos backend.

=head1 SYNOPSIS

  use Convos::Core;
  use Convos::Core::Backend::File;
  my $core = Convos::Core->new(backend => Convos::Core::Backend::File->new);

=head1 OBJECT GRAPH

=over 2

=item * L<Convos::Core>

=over 2

=item * Has one L<Convos::Core::Backend> objects.

This object takes care of persisting data to disk.

=item * Has many L<Convos::Core::User> objects.

Represents a user of L<Convos>.

=over 2

=item * Has many L<Convos::Core::Connection> objects.

Represents a connection to a remote chat server, such as an
L<IRC|Convos::Core::Connection::Irc> server.

=over 2

=item * Has many L<Convos::Core::Dialog> objects.

This represents a dialog with zero or more users.

=back

=back

=back

=back

All the child objects have pointers back to the parent object.

=head1 ATTRIBUTES

L<Convos::Core> inherits all attributes from L<Mojo::Base> and implements
the following new ones.

=head2 backend

  $obj = $core->backend;

Holds a L<Convos::Core::Backend> object.

=head2 base_url

  $url = $core->base_url;

Holds a L<Mojo::URL> object that holds the public location of this Convos
instance.

=head2 home

  $obj = $core->home;
  $core = $core->home(Mojo::File->new($ENV{CONVOS_HOME});

Holds a L<Mojo::File> object pointing to where Convos store data.

=head2 log

  $log = $core->log;
  $core = $core->log(Mojo::Log->new);

Holds a L<Mojo::Log> object.

=head2 ready

  $bool = $core->ready;

Will be true if the backend has loaded initial data.

=head1 METHODS

L<Convos::Core> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 connect

  $core->connect($connection);

This method will call L<Convos::Core::Connection/connect> either at once
or add the connection to a queue which will connect after an interval.

The reason for queuing connections is to prevent flooding the server.

Note: Connections to "localhost" will not be delayed, unless the first connect
fails.

C<$cb> is optional, but will be passed on to
L<Convos::Core::Connection/connect> if defined.

=head2 connections_by_id

  $collection = $core->connections_by_id($cid);

Finds all L<Convos::Core::Connection> objects where C<id()> matches C<$cid>.

=head2 get_user

  $user = $core->get_user(\%attrs);
  $user = $core->get_user($email);

Returns a L<Convos::Core::User> object or undef.

=head2 get_user_by_uid

  $user = $core->get_user_by_uid($uid);

Returns a L<Convos::Core::User> object or C<undef>.

=head2 new

  $core = Convos::Core->new(%attrs);
  $core = Convos::Core->new(\%attrs);

Object constructor. Builds L</backend> if a classname is provided.

=head2 start

  $core = $core->start;

Will start the backend. This means finding all users and start connections
if state is not "disconnected".

=head2 remove_user_p

  $p = $core->remove_user_p($user)->then(sub { $user });

Used to delete user data and remove the user from C<$core>.

=head2 user

  $user = $core->user(\%attrs);

Returns a new L<Convos::Core::User> object or updates an existing object.

=head2 users

  $users = $core->users;

Returns an array-ref of of L<Convos::Core::User> objects.

=head2 web_url

  $url = $core->web_url($url);

Takes a path, or complete URL, merges it with L</base_url> and returns a new
L<Mojo::URL> object. Note that you need to call L</to_abs> on that object
for an absolute URL.

=head1 SEE ALSO

L<Convos>.

=cut
