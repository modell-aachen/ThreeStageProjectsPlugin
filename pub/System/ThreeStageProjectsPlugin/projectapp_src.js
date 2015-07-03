jQuery(function($) {

    // Milestones twisties
    $('.jqTwisty.milestonetwisty').each(function(){
      var $this = $(this);
      $this.bind('afterOpen.twisty', function() {
        if($this.hasClass('processesInited')) return;
        $this.addClass('processesInited');
        var $process = $($this.attr('data-target')).find('.processes');
        var gate = $process.attr('data-gate');
        if(!gate) return;
        var url = foswiki.getPreference('SCRIPTURL') + '/rest' + foswiki.getPreference('SCRIPTSUFFIX') + '/RenderPlugin/template?render=1;name=TSProjectsMilestoneView;topic=' + foswiki.getPreference('WEB') + '.' + gate + ';expand=processesRows';
        $process.load(url,function(){$process.closest('table').addClass('processTable');});
      });
    });

    // Disable calendar input field
  $('.caldisable .foswikiEditFormDateField').livequery(function() {$(this).attr('readonly', 'readonly');});
});
