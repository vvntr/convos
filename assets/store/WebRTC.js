import adapter from 'webrtc-adapter';
import Reactive from '../js/Reactive';
import WebRTCPeerConnection from './WebRTCPeerConnection';
import {clone} from '../js/util';
import {omnibus} from '../store/Omnibus';

const SCREEN_CAPTURE_ID = 'c0000000-0000-0000-0000-000000000001';

/*
 * https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API
 * https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Protocols
 * https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Connectivity
 * https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation
 *
 * https://webrtc.github.io/test-pages/
 * https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
 * https://github.com/webrtc/test-pages/blob/63a46f73c917ffcdf765bd11622b10bf473eb11c/src/peer2peer/js/main.js
 *
 * https://meetrix.io/blog/webrtc/coturn/installation.html
 *
 * about:webrtc
 */
export default class WebRTC extends Reactive {
  constructor(params) {
    super();

    this.prop('ro', 'enabled', () => !!(this.peerConfig.ice_servers || []).length);
    this.prop('ro', 'videoStream', () => this.localStream.id && this.localStream || null);

    this.prop('rw', 'cameras', []);
    this.prop('rw', 'dialog', null);
    this.prop('rw', 'localStream', {id: ''});
    this.prop('rw', 'microphones', []);
    this.prop('rw', 'peerConfig', {});
    this.prop('rw', 'screenStream', {id: ''});
    this.prop('rw', 'speakers', []);

    this.prop('persist', 'constraints', {audio: true, video: true});

    this.connections = {};
    this.unsubscribe = {};

    // Try to cleanup before we close the window
    this.call = this.call.bind(this);
    this.hangup = this.hangup.bind(this);
    window.addEventListener('beforeunload', this.hangup);
  }

  async call(dialog, constraints) {
    if (this.localStream.id) await this.hangup();
    if (!constraints) constraints = this.constraints;

    this.unsubscribe.dialogRtc = dialog.on('rtc', msg => this._onSignal(msg));
    this.update({constraints, dialog});

    const localStream = await navigator.mediaDevices.getUserMedia(constraints);
    this.update({localStream});
    this._send('call', {});
    this.getDevices();
  }

  async getDevices() {
    const devices = {cameras: [], microphones: [], other: [], speakers: []};
    const enumerateDevices = await navigator.mediaDevices.enumerateDevices();

    const activeTracks = {};
    if (this.localStream.getTracks) {
      this.localStream.getTracks().forEach(track => {
        console.log(track);
        activeTracks[track.kind + 'input'] = track.id; // track.kind == {audio,video}
      });
    }

    enumerateDevices.forEach((dev, i) => {
      const type = dev.kind == 'audioinput' ? 'microphone'
                 : dev.kind == 'audiooutput' ? 'speaker'
                 : dev.kind == 'videoinput' ? 'camera'
                 : 'other';

      const active = activeTracks[dev.kind] ? true : false;
      devices[type + 's'].push({active, id: dev.deviceId, name: dev.label || dev.text || [type, i].join(' ')});
    });

    if (navigator.mediaDevices.getDisplayMedia) {
      devices.cameras.push({active: false, id: SCREEN_CAPTURE_ID, name: 'Share screen'});
    }

    console.log({activeTracks, devices});

    this.update(devices);
  }

  async hangup() {
    if (!this.localStream.id) return;
    this._send('hangup', {});
    this._mapConnections(conn => conn.hangup());
    if (this.localStream.getTracks) this.localStream.getTracks().forEach(track => track.stop());
    if (this.unsubscribe.dialogRtc) this.unsubscribe.dialogRtc();
    this.update({localStream: {id: ''}});
  }

  isMuted(nick, kind = 'audio') {
    const stream = this.peerConnections({nick}).map(conn => conn.remoteStream)[0] || this.localStream;
    if (!stream.id) return true;

    const tracks = kind == 'audio' ? stream.getAudioTracks() : stream.getVideoTracks();
    if (!tracks.length) return true;

    return tracks.filter(track => track.enabled).length == tracks.length ? false : true;
  }

  mute(nick, kind, mute) {
    const stream = this.peerConnections({nick}).map(conn => conn.remoteStream)[0] || this.localStream;
    const tracks = kind == 'audio' ? stream.getAudioTracks() : stream.getVideoTracks();
    tracks.forEach(track => { track.enabled = mute === undefined ? !track.enabled : !mute });
    this.emit('update', this, {});
  }

  peerConnections(filter) {
    return this._mapConnections(conn => {
      if (filter.nick) return conn.nick == filter.nick ? conn : false;
      if (filter.remoteStream) return conn.remoteStream ? conn : false;
      return conn;
    }).filter(Boolean);
  }

  async refreshInfo() {
    // TODO: Should this do anything on the local connection?
  }

  async setDevice(type, deviceId) {
    // Change "speaker"
    if (type == 'speaker') {
      const key = type + 's';
      this[key].forEach(dev => { dev.active == dev.id == deviceId });
      return this.update({[key]: devs});
    }

    // Change "camera" or "microphone"
    const queryMethod = deviceId == SCREEN_CAPTURE_ID ? 'getDisplayMedia' : 'getUserMedia';
    const queryConstraints = {};
    const section = type == 'camera' ? 'video' : 'audio';
    queryConstraints[section] = {};
    queryConstraints[section] = deviceId == SCREEN_CAPTURE_ID ? true : {deviceId};
    console.log(queryMethod, queryConstraints);

    const getTracksMethod = type == 'camera' ? 'getVideoTracks' : 'getAudioTracks';
    const localStream = this.localStream;
    const queryStream = await navigator.mediaDevices[queryMethod](queryConstraints);

    localStream[getTracksMethod]().forEach(track => localStream.removeTrack(track));
    queryStream[getTracksMethod]().forEach(track => localStream.addTrack(track));
    this._mapConnections(conn => conn.updateTracks());

    if (deviceId != SCREEN_CAPTURE_ID) {
      const key = type + 's';
      this[key].forEach(dev => { dev.active == dev.id == deviceId });
      this.update({constraints: {...(this.constraints), [section]: queryConstraints[section]}});
    }
  }

  _connection(msg) {
    const nick = msg.from;

    // Clean up old connections
    if (this.connections[nick] && ['call', 'hangup'].indexOf(msg.type) != -1) {
      this.connections[nick].hangup();
      delete this.connections[nick];
    }

    // Return existing connection
    if (this.connections[nick]) return this.connections[nick];

    // Create connection
    const peerConfig = this._normalizedPeerConfig(this.peerConfig);
    const conn = new WebRTCPeerConnection({localStream: this.localStream, nick, peerConfig});
    conn.on('hangup', () => delete this.connections[nick]);
    conn.on('signal', msg => this._send('signal', msg));
    conn.on('update', () => this.emit('update', this, {}));
    this.emit('connection', (this.connections[nick] = conn));
    return conn;
  }

  _mapConnections(cb) {
    return Object.keys(this.connections).map(nick => cb(this.connections[nick]));
  }

  _normalizedPeerConfig() {
    const config = clone(this.peerConfig);
    config.iceServers = config.ice_servers || [];
    delete config.ice_servers;

    config.iceServers.forEach(s => {
      if (s.credential_type) s.credentialType = s.credential_type;
      delete s.credential_type;
    });

    return config;
  }

  _onSignal(msg) {
    if (msg.type == 'signal') return this._connection(msg).signal(msg);
    if (msg.type == 'call') return this._connection(msg).call(msg);
    if (msg.type == 'hangup') return this._connection(msg).hangup(msg);
  }

  _send(event, msg) {
    if (this.dialog) this.dialog.send({...msg, method: 'rtc', event});
  }
}
