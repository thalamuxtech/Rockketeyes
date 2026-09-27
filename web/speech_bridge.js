// Rockketeyes Web Speech bridge.
// Continuous, interim-result speech recognition with automatic restarts,
// plus a microphone level meter. Called from Dart via dart:js_interop.
(function () {
  'use strict';
  var SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  var GL = window.SpeechGrammarList || window.webkitSpeechGrammarList;

  var rec = null;
  var wanted = false;
  var session = 0;
  var handler = null;
  var restartTimer = null;
  var lastError = null;

  var owner = 0;
  // Phones allow one microphone consumer at a time: a second getUserMedia
  // stream (for the level meter) would silence speech recognition.
  var MOBILE = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || '');

  var audioCtx = null;
  var stream = null;
  var levelTimer = null;

  function emit(type, payload) {
    if (handler) {
      try { handler(type, JSON.stringify(payload || {})); } catch (e) { /* ignore */ }
    }
  }

  function build(lang, words) {
    var r = new SR();
    r.lang = lang || 'en-US';
    r.continuous = true;
    r.interimResults = true;
    r.maxAlternatives = 3;
    if (GL && words && words.length) {
      try {
        var list = new GL();
        list.addFromString('#JSGF V1.0; grammar colors; public <color> = ' + words.join(' | ') + ' ;', 1);
        r.grammars = list;
      } catch (e) { /* grammars unsupported */ }
    }
    r.onstart = function () { emit('start', { session: session }); };
    r.onspeechstart = function () { emit('level', { v: 0.7 }); };
    r.onspeechend = function () { emit('level', { v: 0.0 }); };
    r.onresult = function (ev) {
      var out = [];
      for (var i = ev.resultIndex; i < ev.results.length; i++) {
        var res = ev.results[i];
        var alts = [];
        for (var a = 0; a < res.length; a++) {
          alts.push({ t: res[a].transcript, c: res[a].confidence || 0 });
        }
        out.push({ i: i, final: !!res.isFinal, alts: alts });
      }
      emit('result', { session: session, results: out });
    };
    r.onerror = function (ev) {
      lastError = ev.error || 'unknown';
      emit('error', { session: session, error: lastError });
      if (lastError === 'not-allowed' || lastError === 'service-not-allowed' || lastError === 'audio-capture') {
        wanted = false;
      }
    };
    r.onend = function () {
      emit('end', { session: session });
      if (wanted) {
        clearTimeout(restartTimer);
        restartTimer = setTimeout(function () {
          if (!wanted) return;
          session++;
          try { rec.start(); } catch (e) { /* already started */ }
        }, 60);
      }
    };
    return r;
  }

  function startLevels() {
    if (MOBILE || !navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return;
    navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true } })
      .then(function (s) {
        if (!wanted) { s.getTracks().forEach(function (t) { t.stop(); }); return; }
        stream = s;
        var Ctx = window.AudioContext || window.webkitAudioContext;
        audioCtx = new Ctx();
        var src = audioCtx.createMediaStreamSource(s);
        var an = audioCtx.createAnalyser();
        an.fftSize = 512;
        src.connect(an);
        var buf = new Uint8Array(an.fftSize);
        levelTimer = setInterval(function () {
          an.getByteTimeDomainData(buf);
          var sum = 0;
          for (var i = 0; i < buf.length; i++) { var v = (buf[i] - 128) / 128; sum += v * v; }
          var rms = Math.sqrt(sum / buf.length);
          emit('level', { v: Math.min(1, rms * 4) });
        }, 80);
      })
      .catch(function () { /* meter is optional */ });
  }

  function stopLevels() {
    clearInterval(levelTimer); levelTimer = null;
    if (stream) { stream.getTracks().forEach(function (t) { t.stop(); }); stream = null; }
    if (audioCtx) { try { audioCtx.close(); } catch (e) { /* ignore */ } audioCtx = null; }
  }

  window.rocketeyeSpeech = {
    supported: function () { return !!SR; },
    lastError: function () { return lastError; },
    start: function (lang, wordsCsv, onEvent) {
      if (!SR) { return 0; }
      handler = onEvent;
      wanted = true;
      lastError = null;
      session++;
      var words = wordsCsv ? wordsCsv.split(',') : [];
      if (rec) { try { rec.abort(); } catch (e) { /* ignore */ } }
      rec = build(lang, words);
      try { rec.start(); } catch (e) { emit('error', { error: 'start-failed' }); return 0; }
      startLevels();
      owner++;
      return owner;
    },
    // Only the screen that started listening can stop it.
    stop: function (id) {
      if (id && id !== owner) return;
      wanted = false;
      clearTimeout(restartTimer);
      if (rec) { try { rec.abort(); } catch (e) { /* ignore */ } }
      rec = null;
      stopLevels();
    }
  };
})();
