package Telemetry::Any;
use 5.008001;
use strict;
use warnings;

use Carp;

use base 'Devel::Timer';

our $VERSION = "0.03";

my $telemetry = __PACKAGE__->new();

sub import {
    my ( $class, $var ) = @_;

    return if !defined $var;

    my $saw_var;
    if ( $var =~ /^\$(\w+)/x ) {
        $saw_var = $1;
    }
    else {
        croak('Аrgument must be a variable');
    }

    my $caller = caller();

    no strict 'refs';    ## no critic (TestingAndDebugging::ProhibitNoStrict)
    my $varname = "${caller}::${saw_var}";
    *$varname = \$telemetry;

    return;
}

## calculate total time (start time vs last time)
sub total_time {
    my ($self) = @_;

    return Time::HiRes::tv_interval( $self->{times}->[0], $self->{times}->[ $self->{count} - 1 ] );
}

sub report {
    my ( $self, %args ) = @_;

    if ( defined $args{format} && $args{format} eq 'table' ) {
        $self->print( ref($self) . ' Report -- Total time: ' . sprintf( '%.4f', $self->total_time() ) . ' secs' );
    }

    if ( $args{collapse} ) {
        return $self->_report_collapse(%args);
    }
    else {
        return $self->_report(%args);
    }
}

sub _report {
    my ( $self, %args ) = @_;

    if ( defined $args{format} && $args{format} eq 'table' ) {
        $self->print('Interval  Time    Percent');
        $self->print('----------------------------------------------');
    }

    ## sort interval structure based on value

    @{ $self->{intervals} } = sort { $b->{value} <=> $a->{value} } @{ $self->{intervals} };

    ##
    ## report of each time space between marks
    ##

    for my $i ( @{ $self->{intervals} } ) {
        ## skip first time (to make an interval,
        ## compare the current time with the previous one)

        next if ( $i->{index} == 0 );

        my $msg = sprintf(
            '%02d -> %02d  %.4f  %5.2f%%  %s -> %s',
            ( $i->{index} - 1 ),
            $i->{index}, $i->{value},    #$self->print("\n");
            ( ( $i->{value} / $self->total_time() ) * 100 ),
            $self->{label}->{ ( $i->{index} - 1 ) },
            $self->{label}->{ $i->{index} }
        );

        $self->print($msg);
    }

    return 1;
}

sub _report_collapse {
    my ( $self, %args ) = @_;

    if ( defined $args{format} && $args{format} eq 'table' ) {
        $self->print('Count     Time    Percent');
        $self->print('----------------------------------------------');
    }

    $self->_calculate_collapsed;

    my $c       = $self->{collapsed};
    my $sort_by = $args{sort_by} || 'time';
    my @labels  = sort { $c->{$b}->{$sort_by} <=> $c->{$a}->{$sort_by} } keys %$c;
    foreach my $label (@labels) {
        my $count = $c->{$label}->{count};
        my $time  = $c->{$label}->{time};
        my $msg
            = sprintf( '%8s  %.4f  %5.2f%%  %s', ( $count, $time, ( ( $time / $self->total_time() ) * 100 ), $label ) );
        $self->print($msg);
    }

    return 1;
}

sub reset {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($self) = @_;

    %{$self} = (
        times => [],
        count => 0,
        label => {},
    );

    return $self;
}

1;
__END__

=encoding utf-8

=head1 NAME

Telemetry::Any - It's new $module

=head1 SYNOPSIS

    use Telemetry::Any;

=head1 DESCRIPTION

Telemetry::Any is ...

=head1 LICENSE

Copyright (C) Mikhail Ivanov.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Mikhail Ivanov E<lt>m.ivanych@gmail.comE<gt>

=cut

