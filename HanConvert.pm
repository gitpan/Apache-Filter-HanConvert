# $File: //member/autrijus/Apache-Filter-HanConvert/HanConvert.pm $ $Author: autrijus $
# $Revision: #1 $ $Change: 2677 $ $DateTime: 2002/12/11 16:52:29 $

package Apache::Filter::HanConvert;
$Apache::Filter::HanConvert::VERSION = '0.01';

use strict;
use warnings;

=head1 NAME

Apache::Filter::HanConvert - Filter between Chinese variant and encodings

=head1 VERSION

This document describes version 0.01 of Apache::Filter::HanConvert, released
December 12, 2002.

=head1 SYNOPSIS

In httpd.conf:

    PerlModule Apache::Filter::HanConvert
    PerlOutputFilterHandler Apache::Filter::HanConvert
    PerlSetVar HanConvertFromVariant "traditional"

=head1 DESCRIPTION

This module utilizes the B<Encode::HanConvert> module with B<Apache2>'s
output filtering mechanism, to provide a flexible and customizable
solution for serving multiple encoding/variants from the same source
documents.

From the settings in L</SYNOPSIS>, the server would negotiate with the
client's browser about the Traditional/Simplified choice (C<zh-cn> and
C<zh> means Simplified, other C<zh-*> means Traditional), and serve
UTF-8 documents by default.

If you want to use other encodings, try adding these lines:

    PerlSetVar HanConvertFromEncoding "UTF-8"
    PerlSetVar HanConvertToEncodingTraditional "big5"
    PerlSetVar HanConvertToEncodingSimplified "gbk"

Finally, if you'd like to dictate it to always convert to a specific
variant/encoding, use this:

    PerlSetVar HanConvertToVariant "simplified"
    PerlSetVar HanConvertToEncoding "gbk"

=cut

use Encode ();
use Encode::HanConvert 0.10 ();

use Apache2 ();
use Apache::Filter ();
use Apache::RequestRec ();

use APR::Brigade ();
use APR::Bucket ();

use Apache::Const -compile => qw(OK DECLINED);
use APR::Const -compile => ':common';

my %variants = (
    'TS'    => 'trad-simp',
    'ST'    => 'simp-trad',
    'XS'    => 'trad-simp',
    'XT'    => 'simp-trad',
);

my %encodings = (
    'T'	    => 'HanConvertToEncodingTraditional',
    'S'	    => 'HanConvertToEncodingSimplified',
);

sub Apache::Filter::HanConvert::handler {
    my($filter, $bb) = @_;

    my $r = $filter->r;

    my $from_variant  = uc(substr($r->dir_config("HanConvertFromVariant"), 0, 1)) || 'X';
    my $from_encoding = $r->dir_config("HanConvertFromEncoding") || 'UTF-8';
    my $to_variant    = uc(substr($r->dir_config("HanConvertToVariant"), 0, 1));
    my $to_encoding   = $r->dir_config("HanConvertToEncoding");

    if (!$to_variant) {
	my $langs = $r->headers_in->get('Accept-Language');

	$to_variant = (($1 and $1 ne 'cn') ? 'T' : 'S')
	    if $langs =~ /\bzh(?:-(tw|cn|hk|sg))?\b/;
    }

    return Apache::DECLINED unless $to_variant;

    $to_encoding ||= $r->dir_config($encodings{$to_variant}) || 'UTF-8';

    return Apache::DECLINED if $from_encoding eq $to_encoding
			    and $from_variant eq $to_variant;

    my $var_enc = $variants{"$from_variant$to_variant"} || 'UTF-8';

    my $c = $filter->c;
    my $bb_ctx = APR::Brigade->new($c->pool, $c->bucket_alloc);
    my $data = '';

    while (!$bb->empty) {
	my $bucket = $bb->first;

	$bucket->remove;

	if ($bucket->is_eos) {
	    $bb_ctx->insert_tail($bucket);
	    last;
	}

	my $buffer;
	my $status = $bucket->read($buffer);
	return $status unless $status == APR::SUCCESS;

	Encode::from_to($buffer, $from_encoding => 'UTF-8', Encode::FB_HTMLCREF)
	    if $from_encoding ne 'UTF-8';

	if ($var_enc eq $to_encoding) {
	    $bucket = APR::Bucket->new( $buffer );
	}
	elsif ($data .= $buffer) {
	    $bucket = APR::Bucket->new( Encode::encode(
		$to_encoding, Encode::decode($var_enc, $data, Encode::FB_QUIET)
	    ) );
	}

	$bb_ctx->insert_tail($bucket);
    }

    my $rv = $filter->next->pass_brigade($bb_ctx);
    return $rv unless $rv == APR::SUCCESS;

    Apache::OK;
}

1;

__END__

=head1 SEE ALSO

L<Apache2>, L<Encode::HanConvert>, L<Encode>

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>

=head1 COPYRIGHT

Copyright 2002 by Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
