# See bottom of file for default license and copyright information

package Foswiki::Plugins::ThreeStageProjectsPlugin;

use strict;
use warnings;

use Foswiki::Func    ();    # The plugins API
use Foswiki::Plugins ();    # For the API version

our $VERSION = '1.0';
our $RELEASE = '1.0';

our $SHORTDESCRIPTION = 'Three staged projects application.';

our $NO_PREFS_IN_TOPIC = 1;

our $count;
our $metacache;
our $allowTick;

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 2.0 ) {
        Foswiki::Func::writeWarning( 'Version mismatch between ',
            __PACKAGE__, ' and Plugins.pm' );
        return 0;
    }

    Foswiki::Func::registerRESTHandler(
        'copyautoinc', \&_copyautoinc,
        http_allow => 'POST' );

    Foswiki::Func::registerRESTHandler(
        'autoinc', \&_autoinc,
        http_allow => 'POST' );

    Foswiki::Func::registerRESTHandler(
        'updateBase', \&_updateBase,
        http_allow => 'POST' );

    Foswiki::Func::registerRESTHandler(
        'tick', \&_tick,
        http_allow => 'POST' );

    Foswiki::Func::registerTagHandler(
        'TICK', \&_TICK );

    Foswiki::Func::registerTagHandler(
        'HASOPENTICKS', \&_HASOPENTICKS );

    $count = 0;
    undef $metacache;
    undef $allowTick;

    # Plugin correctly initialized
    return 1;
}

sub beforeSaveHandler {
    my ( $text, $topic, $web, $meta ) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    return unless $query->param('ChangePrefsPlugin');

    foreach my $param ( $query->param() ) {
        if ($param =~ m#RemoveField (.*) Name#) {
            my $rule = $1;
            my $field = $query->param($param) || $rule;
            my $topicCondition = $query->param("RemoveField $rule Topics");
            next if defined $topicCondition && !$topic =~ m#$topicCondition#;
            my $condition = $query->param("RemoveField $rule Condition");
            if ( defined $condition ) {
                $condition = Foswiki::Func::decodeFormatTokens($condition);
                $condition = Foswiki::Func::expandCommonVariables($condition);
                next unless Foswiki::Func::isTrue($condition);
            }
            $meta->remove('FIELD', $field);
        } elsif ($param =~ m#ChangeField (.*) Name#) {
            my $rule = $1;
            my $field = $query->param($param) || $rule;
            my $topicCondition = $query->param("ChangeField $rule Topics");
            next if defined $topicCondition && !$topic =~ m#$topicCondition#;
            my $condition = $query->param("ChangeField $rule Condition");
            if ( defined $condition ) {
                $condition = Foswiki::Func::decodeFormatTokens($condition);
                $condition = Foswiki::Func::expandCommonVariables($condition);
                next unless Foswiki::Func::isTrue($condition);
            }
            my $val = $query->param("ChangeField $rule Value");
            next unless defined $val;
            $val = Foswiki::Func::decodeFormatTokens($val);
            $val = Foswiki::Func::expandCommonVariables($val);
            $meta->remove('FIELD', $field);
            $meta->putKeyed('FIELD', { name=>$field, attributes=>"", title=>$field, value=>$val }); # TODO: get attributes, title from form
        } elsif ($param =~ m#ClearTextTopic#) {
            my $topicCondition = $query->param("ClearText Topics");
            next if defined $topicCondition && !$topic =~ m#$topicCondition#;
            my $condition = $query->param("ClearText_Condition");
            if ( defined $condition ) {
                $condition = Foswiki::Func::decodeFormatTokens($condition);
                $condition = Foswiki::Func::expandCommonVariables($condition);
                next unless Foswiki::Func::isTrue($condition);
            }
        }
    }
}

sub _copyautoinc {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $templateWeb = $query->param('srcweb');
    return 'Missing source' unless $templateWeb; # XXX
    ($templateWeb, undef) = Foswiki::Func::normalizeWebTopicName($templateWeb, $Foswiki::cfg{HomeTopicName});
    return "Template does not exist: $templateWeb" unless Foswiki::Func::webExists($templateWeb);

    my $targetWeb = $query->param('targetweb');
    return 'Missing targetweb' unless $targetWeb;
    return "Missing AUTOINC00... in targetweb: $targetWeb" unless $targetWeb =~ m#(.*)AUTOINC(0+)(.*)#;
    my $prefix = $1;
    my $numbers = $2;
    my $suffix = $3;

    # resolve AUTOINC
    my $webObject = Foswiki::Meta->new( $session, $targetWeb );
    my $start = 0;
    my $pad = length($numbers);

    my @webs = Foswiki::Func::getListOfWebs();
    my $it = new Foswiki::ListIterator(\@webs);
    while ( $it->hasNext() ) {
        my $tn = $it->next();
        next unless $tn =~ /^${prefix}(\d+)/;
        $start = $1 + 1 if ( $1 >= $start );
    }
    my $next = sprintf( "%0${pad}d", $start );
    $targetWeb = "$prefix$next$suffix";

    Foswiki::Func::createWeb($targetWeb, $templateWeb);

    my $srcWebObject = Foswiki::Meta->new( $session, $templateWeb );
    my $topicIt = $srcWebObject->eachTopic();
    while($topicIt->hasNext()) {
        my $topic = $topicIt->next();
        my ($meta, $text) = Foswiki::Func::readTopic($templateWeb, $topic);
        my $newMeta = new Foswiki::Meta($session, $targetWeb, $topic);
        $newMeta->copyFrom($meta);

        next if ( $topic =~ m#^Web# && $topic ne $Foswiki::cfg{HomeTopicName} ); # trigger (before|after)SaveHandlers for WebHome
        Foswiki::Func::saveTopic($targetWeb, $topic, $newMeta, $text, { forcenewrevision => 1 });
    }

    my $url = Foswiki::Func::getScriptUrl(
        $targetWeb, $Foswiki::cfg{HomeTopicName}, 'view'
    );
    Foswiki::Func::redirectCgiQuery( $query, $url, 0 );
    return undef;
}

sub _autoinc {
    my ($session) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $templatetopic = $query->param('templatetopic');
    return 'Missing source' unless $templatetopic; # XXX
    (my $templateweb, $templatetopic) = Foswiki::Func::normalizeWebTopicName(undef, $templatetopic);
    return "Template does not exist: $templateweb.$templatetopic" unless Foswiki::Func::topicExists($templateweb, $templatetopic);

    my $targetwebtopic = $query->param('targetwebtopic');
    return 'Missing targetwebtopic' unless $targetwebtopic;
    my ($targetweb, $targettopic) = Foswiki::Func::normalizeWebTopicName(undef, $targetwebtopic);
    return "Target web '$targetweb' does not exist" unless Foswiki::Func::webExists($targetweb);
    return "Missing AUTOINC00... in targettopic: $targettopic" unless $targettopic =~ m#(.*)AUTOINC(0+)(.*)#;
    my $prefix = $1;
    my $numbers = $2;
    my $suffix = $3;
    return 'Missing prefix' unless $prefix;
    return 'Missing suffix' unless $suffix;

    return 'Template topic is missing suffix' unless $templatetopic =~ m#(.*)$suffix$#;
    my $templateprefix = $1;

    my $masters = {};
    foreach my $param ($query->param()) {
        next unless $param =~ m#slave_(.*)#;
        my $master = $1;
        foreach my $slave ( split(/,/, $query->param($param) ) ) {
            $slave =~ s#^\s+##;
            $slave =~ s#\s+##;
            $masters->{$slave} = $master;
        }
    }

    my $suffixes = $query->param('suffixes');
    return 'Missing suffixes' unless $suffixes;
    $suffixes =~ s#^\s*##;
    $suffixes =~ s#\s*$##;
    my @suffixlist = split(/\s*,\s*/, $suffixes);
    my @templatetopics = ();
    my @templatewebs = ();
    return 'Missing suffixes after split' unless scalar @suffixlist;
    foreach my $eachsuffix ( @suffixlist ) {
        my $eachtemplate = $query->param("${eachsuffix}Template");
        return "Missing template parameter for $eachsuffix (   * Set ${eachsuffix}Template = ...)" unless $eachtemplate;
        my $eachtemplateweb;
        ($eachtemplateweb, $eachtemplate) = Foswiki::Func::normalizeWebTopicName('', $eachtemplate);
        return "Missing template file: $eachtemplateweb.$eachtemplate" unless Foswiki::Func::topicExists($eachtemplateweb, $eachtemplate);
        push(@templatetopics, $eachtemplate);
        push(@templatewebs, $eachtemplateweb);
    }

    my $urlparams = _getUrlParams($query, $suffix);

    # creating base topic

    # resolve AUTOINC
    my $webObject = Foswiki::Meta->new( $session, $targetweb );
    my $it = $webObject->eachTopic();
    my $start = 0;
    my $pad = length($numbers);

    while ( $it->hasNext() ) {
        my $tn = $it->next();
        next unless $tn =~ /^${prefix}(\d+)/;
        $start = $1 + 1 if ( $1 >= $start );
    }
    my $next = sprintf( "%0${pad}d", $start );
    $targettopic = "$prefix$next$suffix";

    _copyTopic($session, $templateweb, $templatetopic, $targetweb, $targettopic, undef, undef, $urlparams->{$suffix});
    for(my $i = 0; $i < scalar @templatetopics; $i++) {
        my $urlparam;
        my $parent;
        my $master = $masters->{$suffixlist[$i]};
        if($master) {
            $urlparam = $urlparams->{$suffixlist[$i]};
            $urlparam->{Update} = {
                ($urlparam->{Update} ? %{$urlparam->{Update}} : ()),
                ($urlparams->{$master}->{Update} ? %{$urlparams->{$master}->{Update}} : ())
            };
            $parent = "$prefix$next$master";
        } else {
            $urlparam = $urlparams->{$suffixlist[$i]};
            $parent = $targettopic;
        }
        _copyTopic($session, $templatewebs[$i], $templatetopics[$i], $targetweb, "$prefix$next$suffixlist[$i]", $targetweb, $parent, $urlparam);
    }

    my $url = Foswiki::Func::getScriptUrl(
        $targetweb, $targettopic, 'view',
    );
    Foswiki::Func::redirectCgiQuery( undef, $url );
    return undef;
}

sub _getUrlParams {
    my ($query, $basesuffix) = @_;

    my $urlparams = {};

    foreach my $param ($query->param()) {
        next unless ($param =~ m#^[A-Z]#);
        # Action_Suffix_Name or Action_Name
        # Update_$suffix_$field SetField_$suffix_$field SetForm_$suffix Append_$suffix RemoveField_$suffix SetPref_$suffix_$preference
        # Anything else is a formfield
        if($param =~ m#^(SetForm|RemoveField|RemovePref|Append)_(.*)$#) {
            $urlparams->{$2}->{$1} = $query->param($param);
        } elsif($param =~ m#^(SetForm|RemoveField|RemovePref|Append)$#) {
            $urlparams->{$basesuffix}->{$1} = $query->param($param);
        } elsif($param =~ m#^([A-Za-z]*)_(.*?)_(.*)$#) {
            $urlparams->{$2}->{$1}->{$3} = $query->param($param);
        } elsif($param =~ m#^([A-Za-z]*)_(.*?)$#) {
            $urlparams->{$basesuffix}->{$1}->{$2} = $query->param($param);
        } else {
            next if ($param =~ m#Template$#);
            $urlparams->{$basesuffix}->{Update}->{$param} = $query->param($param);
        }
    }

    return $urlparams;
}

sub _updateBase {
    my ($session) = @_;

    # XXX TODO: action_cancel

    my $query = Foswiki::Func::getCgiQuery();
    my $baseweb = $query->param('baseweb');
    my $basetopic = $query->param('basetopic');
    return 'Missing parameter: basetopic' unless $basetopic;
    ($baseweb, $basetopic) = Foswiki::Func::normalizeWebTopicName($baseweb, $basetopic);
    return "Topic $baseweb.$basetopic does not exist!" unless Foswiki::Func::topicExists($baseweb, $basetopic);
    # XXX todo: ACLs

    my $basesuffix = $query->param('basesuffix') || '';
    my $base = $basetopic;
    $base =~ s#$basesuffix$##;

    my $urlparams = _getUrlParams($query, $basesuffix);

    foreach my $suffix ( keys %$urlparams ) {
        my $eachtopic = "$base$suffix";
        my ($meta, $text) = Foswiki::Func::readTopic($baseweb, $eachtopic);
        my $dirty = 0;
        foreach my $param ( keys %{$urlparams->{$suffix}->{Update}} ) {
            my $old = $meta->get('FIELD', $param);
            unless ( $old && $old->{value} eq $urlparams->{$suffix}->{Update}->{$param} ) {
                $meta->putKeyed( 'FIELD', { name => $param, title => $param, value => $urlparams->{$suffix}->{Update}->{$param} } );
                $dirty = 1;
            }
        }
        if($dirty) {
            Foswiki::Func::saveTopic($baseweb, $eachtopic, $meta, $text, { forcenewrevision => 1 });
        }
    }

    my $url = Foswiki::Func::getScriptUrl(
        $baseweb, $basetopic, 'view',
    );
    Foswiki::Func::redirectCgiQuery( undef, $url );
    return undef;
}

sub _copyTopic {
    my ( $session, $srcWeb, $srcTopic, $targetWeb, $targetTopic, $parentWeb, $parentTopic, $params ) = @_;

    my ($meta, $text) = Foswiki::Func::readTopic($srcWeb, $srcTopic);
    my $newMeta = new Foswiki::Meta($session, $targetWeb, $targetTopic);
    $newMeta->copyFrom($meta);
    $newMeta->remove('WORKFLOW');
    $newMeta->remove('PREFERENCE', 'WORKFLOW');
    $newMeta->remove('PREFERENCE', 'ALLOWTOPICCOMMENT');

    # Handle actions in meta
    my $setPref = $newMeta->get('PREFERENCE', 'SetPref');
    my $remField = $newMeta->get('PREFERENCE', 'RemoveField');
    my $append = $newMeta->get('PREFERENCE', 'Append');

    if($setPref) {
        $setPref = Foswiki::Func::expandCommonVariables($setPref, $meta);
        $newMeta->remove('PREFERENCE', 'SetPref');
        while($setPref->{value} =~ m#"([^" ]+?)\s*=\s*((?:[^"]|\\")*?)"#g) {
            my $pref = $1;
            my $val = $2;
            $val =~ s#\\"#"#g;
            $newMeta->remove('PREFERENCE', $pref);
            $newMeta->put('PREFERENCE', { name => $pref, value => $val });
        }
    }

    if($remField) {
        $newMeta->remove('PREFERENCE', 'RemoveField');
        while($remField->{value} =~ m#([^,\s]+)#g) {
            my $field = $1;
            $newMeta->remove('FIELD', $field);
        }
    }

    if($append) {
        $newMeta->remove('PREFERENCE', 'Append');
        my $appendValue = Foswiki::Func::decodeFormatTokens($append->{value});
        $appendValue = Foswiki::Func::expandCommonVariables($appendValue, $newMeta);
        $text .= $appendValue;
    }
    # /Handle actions in meta

    # Handle actions in params
    if($params->{SetPref}) {
        foreach my $pref ( keys %{$params->{SetPref}} ) {
            my $val = Foswiki::Func::decodeFormatTokens($params->{SetPref}->{$pref});
            $val = Foswiki::Func::expandCommonVariables($val, $meta);
            $newMeta->remove('PREFERENCE', $pref);
            $newMeta->put('PREFERENCE', { name => $pref, value => $val });
        }
    }

    if($params->{RemoveField}) {
        while($params->{RemoveField} =~ m#([^,\s]+)#g) {
            my $field = $1;
            $newMeta->remove('FIELD', $field);
        }
    }

    if($params->{RemovePref}) {
        while($params->{RemovePref} =~ m#([^,\s]+)#g) {
            my $field = $1;
            $newMeta->remove('PREFERENCE', $field);
        }
    }

    if($params->{SetForm}) {
        $newMeta->remove('FORM');
        $newMeta->put('FORM', { name => $params->{SetForm} });
    }

    if($params->{Append}) {
        my $appendValue = Foswiki::Func::decodeFormatTokens($params->{Append});
        $appendValue = Foswiki::Func::expandCommonVariables($appendValue, $newMeta);
        $text .= $appendValue;
    }

    foreach my $field ( keys %{$params->{Update}} ) {
        $newMeta->putKeyed('FIELD', { name => $field, title=> $field, value => $params->{Update}->{$field}});
    }
    # /Handle actions in params

    if($parentTopic) {
        my $parent = $parentTopic;
        $parent = "$parentWeb.$parent" if $parentWeb && $parentWeb ne $targetWeb;
        $newMeta->put('TOPICPARENT', { name => $parent });
    }

    # insert checkboxes
    $text =~ s#(<table.*?</table)#tickTable($1)#igmes;

    $newMeta->text($text);
    $newMeta->save();
    my $newtopic = $newMeta->topic();
    foreach my $attachment ( $meta->find('FILEATTACHMENT') ) {
        my $name = $attachment->{name};
        Foswiki::Func::copyAttachment($srcWeb, $srcTopic, $name, $targetWeb, $newtopic);
    }
}

sub tickTable {
    my ($table) = @_;

    if($table =~ m#<tr|<th#g) { # skip first row/header
        $table =~ s#\G(.*?<tr[^>]*>\s*(?:<!--.*?-->)?<td[^>]*>.*?)(</td)#$1 \%TICK\%$2#gms;
    } else {
        Foswiki::Func::writeWarning("table didn't match: $table");
    }

    return $table;
}

sub _tick {
    my ($session) = @_;
    my $query = Foswiki::Func::getCgiQuery();

    my $count = $query->param('count');
    return 'Missing param: Count' unless defined $count;

    my $rev = $query->param('rev');
    return 'Missing param: rev' unless defined $rev;

    my $date = $query->param('date');
    return 'Missing param: date' unless defined $date;

    my $webtopic = $query->param('webtopic');
    return 'Missing param: webtopic' unless defined $webtopic;

    my $tick = $query->param('tick');

    my ( $web, $topic ) = Foswiki::Func::normalizeWebTopicName( undef, $webtopic );
    return "Topic not found: $web.$topic" unless Foswiki::Func::topicExists($web, $topic);

    my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);
    my ($storedDate, $storedAuthor, $storedRev) = $meta->getRevisionInfo();
    return "Date mismatch: stored is $storedDate, requested was $date" unless $storedDate eq $date;
    return "Revision mismatch: stored is $storedRev, requested was $rev" unless $storedRev eq $rev;


    my $n;
    $text =~ s#\%TICK((?:{[^}]*})?)\%#substTick($count, $n++, $1, $tick)#eg;

    # Until the bypass context in KVPPlugin is released:
    $meta->text($text);
    $meta->saveAs($web, $topic, { minor => 1, dontlog => 1, forcenewrevision => 1 });
    # Then this can change to Foswiki::Func::saveTopic($web, $topic, $meta, $text, { minor => 1, dontlog => 1, forcenewrevision => 1 });

    my $url = Foswiki::Func::getScriptUrl(
        $web, $topic, 'view',
    );
    Foswiki::Func::redirectCgiQuery( undef, $url );
    return
}

sub substTick {
    my ( $count, $n, $params, $tick ) = @_;

    if($params) {
        $params =~ s#^{##;
        $params =~ s#}$##;
        $params .= ' ' if $params;
    } else {
        $params = '';
    }
    if($n eq $count) {
        $params =~ s#ticked=".*?"##;
        $params .= 'ticked="1"' if $tick eq 'on';
    }
    $params = "{$params}" if $params;
    return "\%TICK$params\%";
}

sub _TICK {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $n = $count;
    $count++;

    my $attribs = '';

    $attribs .= 'checked="checked" label="%MAKETEXT{"done"}%" ' if $attributes->{ticked};

    my $text;
    unless ( $metacache ) {
        ($metacache, $text) = Foswiki::Func::readTopic($web, $topic);
        $allowTick = Foswiki::Func::expandCommonVariables('%WORKFLOWALLOWS{"allowtick"}%', $topic, $web, $metacache);
    }

    my ($date, $author, $rev) = $metacache->getRevisionInfo();

    $attribs .= (($allowTick) ? 'onchange="$(this).closest(\'form\').submit()"' : 'disabled="disabled"');
    my $tick = <<TICK;
<input name="tick" value="on" type="checkbox" $attribs />
TICK
    $tick = <<FORM if $allowTick;
<form method='post' action='%SCRIPTURL{rest}%/ThreeStageProjectsPlugin/tick' onsubmit='\$.blockUI && \$.blockUI(); 1'>
  $tick
  <input type='hidden' name='count' value='$n' />
  <input type='hidden' name='date' value='$date' />
  <input type='hidden' name='rev' value='$rev' />
  <input type='hidden' name='webtopic' value='$web.$topic' />
</form>
FORM

    return $tick;
}

sub _HASOPENTICKS {
    my ( $session, $attributes, $topic, $web ) = @_;

    my $text;
    if($metacache) {
        $text = $metacache->text();
    } else {
        ($metacache, $text) = Foswiki::Func::readTopic($web, $topic);
    }

    if($text =~ m#\%TICK\%|\%TICK{[^}]*ticked="[^1]"[^}]*}\%#m) {
        return 1;
    }
    return 0;
}

1;

__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2014 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
