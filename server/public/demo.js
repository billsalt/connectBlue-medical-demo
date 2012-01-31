$(function () {
    var firstTime = 0;
    var lastTime = 0;
    var timeOffset = 0;
    var yrange = 6000;
    var xrange = 1000;
    var averageValue = 32768;
    var stopped = false;
    var options = {
        lines: { show: true },
        points: { show: false },
	xaxis: { show: false, min: lastTime - xrange, max: lastTime },
//	yaxis: { show: false, min: 32768 - yrange/2, max: 32768 + yrange/2 }
	yaxis: { show: false }
    };
    var data = [];
    var placeholder = $("#placeholder");
    var lastReport = null;
    var ref = 0;

    function fetchData() {
      $.ajax({
          url: "/data.json",
          data: { last_sample: lastTime  },
          method: 'GET',
          dataType: 'json',
          success: onDataReceived
      });
    }

    // returns new 2-element array with time shifted
    // by value of ref
    var shiftData = function(a) {
      return [a[0] + ref, a[1]];
    }

    $("#stopbutton").click( function() {
	    stopped = !stopped;
	    if (stopped) {
		$("#stopbutton").text("START");
	    } else {
		$("#stopbutton").text("STOP");
		fetchData();
	    }
    });

    // series properties:
    // 'alarms' = <int>  bitmask
    // 'spO2' = <int> percent
    // 'hr' = <int> heart rate, BPM
    // 'battV' = <float> battery voltage
    // 'ref' = <int> lastSample
    // 'ecg' = [[t,v],[t,v] ... ]
    //    where t = timestamps in msec since lastSample
    //      and v = 16-bit unsigned value 
    function onDataReceived(series) {
      lastReport = series;
      ref = series.ref;
      var shifted = series.ecg.map(shiftData);
      // data = data + shifted
      data = data.concat(shifted);
      // chop data to last N points
      if (data.length > 800) {
        data = data.slice(data.length - 800);
      }
      lastTime = options.xaxis.max = data[data.length - 1][0];
      timeOffset = lastTime;
      firstTime = options.xaxis.min = data[0][0];
      $.plot($("#placeholder"), [ data ], options);
      $("#hr .value").text(series.hr || '--');
      $("#spO2 .value").text(series.spO2 || '--');
      $("#batt .value").text(series.battV || '--');
      if (!stopped) { fetchData(); }
    }

    function scrollGraph() {
    }

    fetchData();
    setTimeout(scrollGraph(), 100);
});
