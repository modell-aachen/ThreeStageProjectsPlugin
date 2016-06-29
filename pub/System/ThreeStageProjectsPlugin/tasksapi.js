(function($) {
  var beforeSaveTask = function(evt, task) {
    var opts = $(this).data('tasktracker_options');
    var query = $.parseJSON(opts.query);
    task.Milestone = query.Milestone;

    var p = foswiki.preferences;
    if (task.Context == 'any' && /Base$/.test(p.TOPIC)) {
      task.Context = p.WEB + '.' + p.TOPIC.replace('Base', task.Milestone);
    }

    return task;
  };

  $(document).ready( function() {
    $('body').on('beforeSave', '.tasktracker', beforeSaveTask);
  });
})(jQuery);
