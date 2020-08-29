import adapter from 'webrtc-adapter';
import Reactive from '../js/Reactive';
import WebRTCPeerConnection from './WebRTCPeerConnection';
import {clone, q, showEl} from '../js/util';
import {viewport} from './Viewport';

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

    this.prop('rw', 'constraints', {audio: true, video: true});
    this.prop('rw', 'localStream', {id: ''});
    this.prop('rw', 'peerConfig', {});

    this.prop('rw', 'cameras', []);
    this.prop('rw', 'microphones', []);
    this.prop('rw', 'speakers', []);

    this.prop('rw', 'videoQuality', '640x360');
    this.prop('ro', 'videoQualityOptions', [
      ['Lo-def',   '320x180'],  // qVGA
      ['Standard', '640x360'],  // VGA
      ['HD',       '1280x720'], // HD
    ]);

    this.connections = {};
    this.unsubscribe = {};

    // Try to cleanup before we close the window
    this.call = this.call.bind(this);
    this.hangup = this.hangup.bind(this);
    window.addEventListener('beforeunload', this.hangup);
  }

  allActiveStreams() {
    return !this.localStream.id ? [] : [this.localStream].concat(this.peerConnections({remoteStream: true}));
  }

  async call() {
    if (this.localStream.id) await this.hangup();
    const localStream = await navigator.mediaDevices.getUserMedia(this.constraints);
    this.update({localStream});
    this._send('call', {});
    this._getDevices();
  }

  async hangup() {
    if (!this.localStream.id) return;
    this._send('hangup', {});
    this._mapPc(pc => pc.hangup());
    if (this.localStream.getTracks) this.localStream.getTracks().forEach(track => track.stop());
    if (this.unsubscribe.dialogRtc) this.unsubscribe.dialogRtc();
    this.update({localStream: {id: ''}});
  }

  isMuted(target, kind = 'audio') {
    const stream = this.peerConnections({target}).map(pc => pc.remoteStream)[0] || this.localStream;
    if (!stream.id) return true;

    const tracks = kind == 'audio' ? stream.getAudioTracks() : stream.getVideoTracks();
    if (!tracks.length) return true;

    return tracks.filter(track => track.enabled).length == tracks.length ? false : true;
  }

  mute(target, kind, mute) {
    const stream = this.peerConnections({target}).map(pc => pc.remoteStream)[0] || this.localStream;
    const tracks = kind == 'audio' ? stream.getAudioTracks() : stream.getVideoTracks();
    tracks.forEach(track => { track.enabled = mute === undefined ? !track.enabled : !mute });
    this.emit('update', this, {});
  }

  peerConnections(filter) {
    return this._mapPc(pc => {
      if (filter.target) return pc.target == filter.target ? pc : false;
      if (filter.remoteStream) return pc.remoteStream ? pc : false;
      return pc;
    }).filter(Boolean);
  }

  _connection(msg) {
    const target = msg.from;

    // Clean up old connections
    if (this.connections[target] && ['call', 'hangup'].indexOf(msg.type) != -1) {
      this.connections[target].hangup();
      delete this.connections[target];
    }

    // Return existing connection
    if (this.connections[target]) return this.connections[target];

    // Create connection
    const peerConfig = this._normalizedPeerConfig(this.peerConfig);
    const pc = new WebRTCPeerConnection({localStream: this.localStream, target, peerConfig});
    pc.on('hangup', () => delete this.connections[target]);
    pc.on('signal', msg => this._send('signal', msg));
    pc.on('update', () => this.emit('update', this, {}));
    this.emit('connection', (this.connections[target] = pc));
    return pc;
  }

  async _getDevices() {
    const devices = {cameras: [], microphones: [], speakers: [], unknown: []};
    const enumerateDevices = await navigator.mediaDevices.enumerateDevices();

    enumerateDevices.forEach(dev => {
      const type = dev.kind == 'audioinput' ? 'microphones'
                 : dev.kind == 'audiooutput' ? 'speakers'
                 : dev.kind == 'videoinput' ? 'cameras'
                 : 'unknown';

      devices[type].push({id: dev.deviceId, name: dev.label || dev.text || dev.deviceId});
    });

    this.update(devices);
  }

  _mapPc(cb) {
    return Object.keys(this.connections).sort().map(target => cb(this.connections[target]));
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
    console.log('send:', event, msg);
  }
}
