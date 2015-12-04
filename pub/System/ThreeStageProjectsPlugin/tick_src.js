jQuery(function($) {
    var readyContent = function($data) {
        $data.find('input[name="tick"]').change(function() {
            $.blockUI && $.blockUI();
            var scrollTop = $(window).scrollTop();
            $(this).closest('form').append($('<input type="text" name="scrollTop" />').hide().val(scrollTop)).submit();
        });
    };

    readyContent($('#modacContentsWrapper'));

    var scrollParam = /scrollTop=([0-9]+)/.exec(window.location.href);
    if(scrollParam) {
        $(window).scrollTop(scrollParam[1]);
    }
});

