$(function () {
	var maxPoints = 800;
	var firstTime = 0;
	var lastTime = 0;
	var lastClock = 0;	// clock time as of last report
	var yrange = 20000;
	var xrange = 10000;
	var averageValue = 32768;
	var stopped = false;
	var options = {
		lines: { show: true },
		points: { show: false },
		xaxis: { show: false, min: 0, max: xrange },
		yaxis: { show: false, min: 0, max: 65535 }
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

	function getAverage(a) {
		var avg = 0;
		a.forEach(function (elem, index, arr) { avg += elem[1]; });
		avg /= a.length;
		return avg;
	}

	// chop data to last maxPoints points
	// get averageValue
	function normalizeData() {
		if (data.length < 1) return;
		if (data.length > maxPoints) { data = data.slice(data.length - maxPoints + 1); }
		lastTime = data[data.length - 1][0];
		firstTime = data[0][0];
	}

	// series properties:
	// 'alarms' = <int>  bitmask
	// 'spO2' = <int> percent
	// 'hr' = <int> heart rate, BPM
	// 'battV' = <float> battery voltage
	// 'ref' = <int> lastSample
	// 'ecg' = [[t,v],[t,v] ... ]
	//	  where t = timestamps in msec since lastSample
	//		and v = 16-bit unsigned value 
	function onDataReceived(series) {
		lastReport = series;
		lastClock = new Date().getTime();
		ref = series.ref;
		var shifted = series.ecg.map(shiftData);
		// data = data + shifted
		data = data.concat(shifted);
		normalizeData();
		averageValue = getAverage(data);
		options.xaxis.max = lastTime;
		options.xaxis.min = lastTime - xrange;
		options.yaxis.max = averageValue + yrange / 2;
		options.yaxis.min = averageValue - yrange / 2;
		$.plot($("#placeholder"), [ data ], options);
		$("#hr .value").text(series.hr || '--');
		$("#spO2 .value").text(series.spO2 || '--');
		$("#batt .value").text(series.battV || '--');
		if (!stopped) {
			fetchData();
			setTimeout(scrollGraph, 100);
		}
	}

	function scrollGraph() {
		var now = new Date().getTime();
		var timeDiff = (now - lastClock);
		if (stopped || timeDiff < 100) return;
		options.xaxis.max = lastTime + timeDiff;
		options.xaxis.min = options.xaxis.max - xrange;
		$.plot($("#placeholder"), [ data ], options);
		setTimeout(scrollGraph, 100);
	}

	$("#stopbutton").click( function() {
		stopped = !stopped;
		$("#stopbutton").text(stopped ? "START" : "STOP");
		if (!stopped) {
			fetchData();
			setTimeout(scrollGraph, 100);
		}
	});

	fetchData();
	setTimeout(scrollGraph, 100);
});

// vim: ts=4 sw=4 noet
