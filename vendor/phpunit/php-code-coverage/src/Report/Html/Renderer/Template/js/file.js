$(() => {
	var $window = $(window),
		$top_link = $("#toplink"),
		$body = $("body, html"),
		offset = $("#code").offset().top;

	$top_link.hide().click((event) => {
		event.preventDefault();
		$body.animate({ scrollTop: 0 }, 800);
	});

	$window.scroll(() => {
		if ($window.scrollTop() > offset) {
			$top_link.fadeIn();
		} else {
			$top_link.fadeOut();
		}
	});

	var $popovers = $(".popin > :first-child");
	$(".popin").on({
		"click.popover": function (event) {
			event.stopPropagation();

			var $container = $(this).children().first();

			//Close all other popovers:
			$popovers.each(function () {
				var $current = $(this);
				if (!$current.is($container)) {
					$current.popover("hide");
				}
			});

			// Toggle this popover:
			$container.popover("toggle");
		},
	});

	//Hide all popovers on outside click:
	$(document).click((event) => {
		if ($(event.target).closest($(".popover")).length === 0) {
			$popovers.popover("hide");
		}
	});

	//Hide all popovers on escape:
	$(document).keyup((event) => {
		if (event.key === "Escape") {
			$popovers.popover("hide");
		}
	});
});
