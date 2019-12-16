package Telemetry::Any;
use 5.008001;
use strict;
use warnings;

use Carp;

use base 'Devel::Timer';

our $VERSION = "0.06";

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

    my @records;
    if ( $args{labels} ) {
        @records = $args{collapse} ? $self->any_labels_collapsed(%args) : $self->any_labels_detailed( $args{labels} );
    }
    else {
        @records = $args{collapse} ? $self->collapsed(%args) : @{ $self->detailed(%args) };
    }

    my $report;

    if ( defined $args{format} && $args{format} eq 'table' ) {
        $report .= ref($self) . ' Report -- Total time: ' . sprintf( '%.4f', $self->total_time() ) . " secs\n";
    }

    if ( $args{collapse} ) {
        if ( defined $args{format} && $args{format} eq 'table' ) {
            $report .= "Count     Time    Percent\n";
            $report .= "----------------------------------------------\n";
        }

        $report .=
            (@records)
            ? join "\n", map { sprintf( '%8s  %.4f  %5.2f%%  %s', $_->{count}, $_->{time}, $_->{percent}, $_->{label}, ) } @records
            : '';

    }
    else {
        if ( defined $args{format} && $args{format} eq 'table' ) {
            $report .= "Interval  Time    Percent\n";
            $report .= "----------------------------------------------\n";
        }

        $report .= (@records)
            ? join "\n", map {
            sprintf(
                '%04d -> %04d  %.4f  %5.2f%%  %s',
                $args{labels} ? $_->{from} : $_->{interval} - 1,
                $args{labels} ? $_->{to} : $_->{interval}, $_->{time}, $_->{percent}, $_->{label},
            )
            } @records
            : '';
    }

    return $report;
}

sub detailed {
    my ( $self, %args ) = @_;

    ## sort interval structure based on value

    @{ $self->{intervals} } = sort { $b->{value} <=> $a->{value} } @{ $self->{intervals} };

    ##
    ## report of each time space between marks
    ##

    my @records;

    for my $i ( @{ $self->{intervals} } ) {
        ## skip first time (to make an interval,
        ## compare the current time with the previous one)

        next if ( $i->{index} == 0 );

        my $record = {    ## no critic (NamingConventions::ProhibitAmbiguousNames
            interval => $i->{index},
            time     => sprintf( '%.6f', $i->{value} ),
            percent  => sprintf( '%.2f', $i->{value} / $self->total_time() * 100 ),
            label    => sprintf( '%s -> %s', $self->{label}->{ $i->{index} - 1 }, $self->{label}->{ $i->{index} } ),
        };

        push @records, $record;
    }

    return @records;
}

sub collapsed {
    my ( $self, %args ) = @_;

    $self->_calculate_collapsed;

    my $c       = $self->{collapsed};
    my $sort_by = $args{sort_by} || 'time';

    my @labels = sort { $c->{$b}->{$sort_by} <=> $c->{$a}->{$sort_by} } keys %$c;

    my @records;

    foreach my $label (@labels) {

        my $record = {    ## no critic (NamingConventions::ProhibitAmbiguousNames
            count   => $c->{$label}->{count},
            time    => sprintf( '%.6f', $c->{$label}->{time} ),
            percent => sprintf( '%.2f', $c->{$label}->{time} / $self->total_time() * 100 ),
            label   => $label,
        };

        push @records, $record;
    }

    return @records;
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

sub any_labels_detailed {
    my ( $self, $input_labels ) = @_;

    my $any_labels  = _filter_input_labels($input_labels);
    my $count_pairs = $self->_define_count_pairs($any_labels);
    return () if ( !scalar %{$count_pairs} );

    my @records = ();

    foreach my $start_count ( keys %{$count_pairs} ) {
        my $finish_count = $count_pairs->{$start_count};
        my $time         = Time::HiRes::tv_interval( $self->{times}->[$start_count], $self->{times}->[$finish_count] );
        my $record       = {
            from    => $start_count,
            to      => $finish_count,
            time    => sprintf( '%.6f', $time ),
            percent => sprintf( '%.2f', $time / $self->total_time() * 100 ),
            label   => sprintf( '%s -> %s', $self->{label}->{$start_count}, $self->{label}->{$finish_count} ),
        };
        push @records, $record;
    }

    return [ sort { $b->{time} <=> $a->{time} } @records ];
}

sub any_labels_collapsed {
    my ( $self, %args ) = @_;

    my $detailed = $self->any_labels_detailed( $args{labels} );
    my $c        = _calculate_any_labels_collapsed($detailed);
    my $sort_by  = $args{sort_by} || 'time';

    my @labels = sort { $c->{$b}->{$sort_by} <=> $c->{$a}->{$sort_by} } keys %$c;

    my @records = ();
    foreach my $label (@labels) {

        my $record = {
            count   => $c->{$label}->{count},
            time    => sprintf( '%.6f', $c->{$label}->{time} ),
            percent => sprintf( '%.2f', $c->{$label}->{time} / $self->total_time() * 100 ),
            label   => $label,
        };
        push @records, $record;
    }

    return @records;
}

sub _filter_input_labels {
    my ($input_labels) = @_;

    my $result = {};
    foreach my $start_label ( keys %{$input_labels} ) {

        if (   $start_label
            && $input_labels->{$start_label}
            && $start_label ne $input_labels->{$start_label} )
        {
            $result->{$start_label} = $input_labels->{$start_label};
        }
    }

    return $result;
}

sub _define_count_pairs {
    my ( $self, $input_labels ) = @_;
    use Data::Dumper;

    my @starts_counts = ();
    my $counts_pairs  = {};
    my @labels_counts = sort { $a <=> $b } keys %{ $self->{label} };

    foreach my $count (@labels_counts) {    #warn 1;
        foreach my $start_label ( keys %{$input_labels} ) {

            if ( $self->{label}->{$count} eq $start_label ) {
                push @starts_counts, $count;
            }
            elsif ( $self->{label}->{$count} eq $input_labels->{$start_label} ) {
                my $start_count = pop @starts_counts;
                if ( defined $start_count ) {
                    $counts_pairs->{$start_count} = $count;
                }
            }
        }
    }
    return $counts_pairs;
}

sub _calculate_any_labels_collapsed {
    my ($records) = @_;

    my %collapsed;
    foreach my $i (@$records) {
        my $label = $i->{label};
        my $time  = $i->{time};
        $collapsed{$label}{time} += $time;
        $collapsed{$label}{count}++;
    }
    return \%collapsed;
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

