// $Id$
$(function() {
	var maxPoints = 2000;
	// Av = 5.4*340 = *1836
	// 65536 counts = 2.85V => 23.7nV/count
	// for 100uV ticks: 100uV/23.7nV = 4222 counts
	var vPerCount = 2.85 / 65536 / (5.4 * 340);
	var	countsPerYGrid = 100e-6 / vPerCount; // input counts/100uV
	var yrange = 14000;
	var xrange = (3.0 * 70 / 60) * 1000; // 3 beats at 70 bpm
	var scrollPeriod = 50;
	var ledThreshold = 1;	// minimum number of 1/75 second points per 1/3 second for greenp or redp to flash LED

	var debugMode = false; // true to print stats
	var numUpdates = 0;
	var numPackets = 0;

	var scrollID = null;
	var blankLedID = null;
	var averageValue = 32768;
	var lastTime = 0; // timestamp as of last report
	var lastClock = 0; // clock time as of last report
	var numInserted = 0;

	// return array of y values corresponding to 100uV ticks
	// but respect average value
	function yTickGenerator(axis) {
		var retval = [], i;
		var ymax = Math.ceil((axis.max - averageValue) / countsPerYGrid);
		var ymin = Math.floor((axis.min - averageValue) / countsPerYGrid);
		for (i = ymin; i < ymax; i++) {
			retval.push(i * countsPerYGrid + averageValue);
		}
		return retval;
	}

	// return formatted string for tick at val
	function yTickFormatter(val, axis) {
		// return ((val-32768)*1.0e6*vPerCount).toFixed(0);
		return "";
	}

	var stopped = false;
	var options = {
		series: {
			lines: {
				show: true
			},
			points: {
				show: false
			}
		},
		margin: 0,
		xaxis: {
			tickLength: 0,
			show: false,
			min: 0,
			max: xrange
		},
		yaxis: {
			tickSize: countsPerYGrid,
			labelWidth: 0,
			show: true,
			min: 0,
			max: 65535,
			tickFormatter: yTickFormatter,
			ticks: yTickGenerator
		}
	};
	var data = [];
	var placeholder = $("#placeholder");

	function fetchData() {
		$.ajax({
			url: "/data.json",
			data: {
				last_sample: lastTime
			},
			method: 'GET',
			dataType: 'json',
			success: onDataReceived
		});
	}

	function lastXValue() {
		return data[data.length - 1][0];
	}

	function lastYValue() {
		return data[data.length - 1][1];
	}

	function getAverage(a, minx) {
		var avg = 0,
		len = 0;
		a.forEach(function(elem, index, arr) {
			if (elem[0] >= minx) {
				avg += elem[1];
				len++;
			}
		});
		return avg / len;
	}

	// chop data to last maxPoints points
	// set axis limits
	// returns last X value
	function normalizeData() {
		if (data.length < 1) return 0;
		if (data.length > maxPoints) {
			data = data.slice(data.length - maxPoints + 1);
		}
		averageValue = getAverage(data, options.xaxis.min);
		// averageValue = getAverage(data, lastXValue()-100);
		options.yaxis.max = averageValue + yrange / 2;
		options.yaxis.min = options.yaxis.max - yrange;
		return options.xaxis.max = lastXValue();
	}

	function blankLed(greystate) {
		$("#led_grey").css("display", greystate)
		$("#led_red").css("display", "none")
		$("#led_green").css("display", "none")
		$("#led_yellow").css("display", "none")
	}

	function updateLEDs(series) {
		var color = null;
		if (series.greenp > ledThreshold) {
			if (series.redp > ledThreshold) {
				color = "#led_yellow";
			}
			else {
				color = "#led_green";
			}
		} else if (series.redp > ledThreshold) {
			color = "#led_red";
		}

		if (color) {
			blankLed("none");
			$(color).css("display", "inherit");
			if (blankLedID) clearTimeout(blankLedID);
			blankLedID = setTimeout(blankLed, 200, "inherit");
		}
	}

	// series properties:
	// 'alarms' = <int>  bitmask
	// 'spO2' = <int> percent
	// 'hr' = <int> heart rate, BPM
	// 'battV' = <float> battery voltage
	// 'ref' = <int> lastSample
	// 'greenp', 'redp' =  number
	// 'ecg' = [[t,v],[t,v] ... ]
	//	  where t = timestamps in msec since lastSample
	//		and v = 16-bit unsigned value 
	function onDataReceived(series) {
		lastClock = (new Date().getTime());
		var ref = series.ref;
		var shifted = series.ecg.map(function(v, i, a) {
			return [v[0] + ref, v[1]];
		});
		// remove inserted points
		if (numInserted > 0) {
			data = data.slice(0, - numInserted).concat(shifted);
			numInserted = 0;
		} else data = data.concat(shifted);
		lastTime = normalizeData();
		$("#hr .value").html(series.hr || '&ndash;&ndash;');
		$("#spO2 .value").html(series.spO2 || '&ndash;&ndash;');
		$("#batt .value").html(series.battV || '&ndash;&ndash;.&ndash');
		updateLEDs(series);
		if (debugMode) {
			$("#greenp").text('green: ' + series.greenp);
			$("#redp").text('red: ' + series.redp);
			$("#packets").text('packets: ' + ++numPackets);
		}
		if (!stopped) {
			fetchData();
		}
	}

	function rePlot() {
		if (data.length < 1) return;
		options.xaxis.min = lastXValue() - xrange;
		$.plot($("#placeholder"), [data], options);
	}

	function scrollGraph() {
		if (data.length < 1) return;
		var now = (new Date().getTime());
		var timeDiff = (now - lastClock);
		if (timeDiff <= 0) return;
		// insert duplicate point to avoid gaps at right of graph
		data = data.concat([[lastTime + timeDiff, lastYValue()]]);
		numInserted++;
		normalizeData();
		rePlot(now);
		if (debugMode) {
			numUpdates++;
			$("#updates").text('updates: ' + numUpdates);
		}
	}

	$("#stopbutton").click(function() {
		stopped = ! stopped;
		$("#stopbutton").val(stopped ? "START": "STOP");
		if (!stopped) {
			scrollID = setInterval(scrollGraph, scrollPeriod);
			fetchData();
		} else {
			clearInterval(scrollID);
		}
	});

	$("#xzoomout").click(function() {
		xrange *= 1.5;
		rePlot();
	});
	$("#xzoomin").click(function() {
		xrange /= 1.5;
		rePlot();
	});
	$("#yzoomout").click(function() {
		yrange *= 1.5;
		normalizeData();
		rePlot();
	});
	$("#yzoomin").click(function() {
		yrange /= 1.5;
		normalizeData();
		rePlot();
	});

	blankLed("inherit");
	fetchData();
	scrollID = setInterval(scrollGraph, scrollPeriod);
});

// vim: ts=4 sw=4 noet

