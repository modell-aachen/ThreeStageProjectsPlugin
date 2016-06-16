(function($) {
  var beforeSaveTask = function(evt, task) {
    var opts = $(this).data('tasktracker_options');
    var query = $.parseJSON(opts.query);
    task.Milestone = query.Milestone;
    return task;
  };

  $(document).ready( function() {
    $('body').on('beforeSave', '.tasktracker', beforeSaveTask);
  });
})(jQuery);
