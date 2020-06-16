<script>
import {onDestroy, onMount} from 'svelte';
import {bytes, ucFirst} from '../js/util';
import {l} from '../js/i18n';

const humanConnectionCatetory = {
  iceConnectionState: 'ICE state',
  iceGatheringState: 'ICE state',
  signalingState: 'Signaling',
};

let refreshTid;

export let conn;
export let rtc;

$: info = $conn.info;
$: connectionState = calculateConnectionState($conn);

onMount(() => { refreshTid = setInterval(() => conn.refreshInfo(), 1000) });
onDestroy(() => clearTimeout(refreshTid));

function calculateConnectionState(conn) {
  const connectionStatePriority = {
    iceConnectionState: {
      'new': 10,
      'checking': 30,
      'connected': 30,
      'completed': 30,
      'failed': 40,
      'closed': 10,
      'disconnected': 10,
    },
    iceGatheringState: {
      'new': 10,
      'gathering': 35,
      'complete': 5,
    },
    signalingState: {
      'closed': 10,
      'have-local-offer': 35,
      'have-remote-offer': 35,
      'have-local-pranswer': 35,
      'have-remote-pranswer': 35,
      'stable': 20,
    },
  };

  return ['iceConnectionState', 'iceGatheringState', 'signalingState'].map(category => {
    const val = conn.info[category];
    console.log('[RTCState]', connectionStatePriority[category][val], (category + ' = ' + val));
    return [connectionStatePriority[category][val] || 2, category, val];
  }).sort((a, b) => b[0] - a[0])[0] || [0, 'signalingState', 'Unknown'];
}

function framerate(conn, type, direction) {
  return Math.round(conn.info[type][direction].framerateMean * 10) / 10;
}

function loss(conn, type, direction) {
  const data = conn.info[type];
  const keys = direction == 'outbound' ? ['droppedFrames'] : ['discardedPackets', 'packetsLost'];
  return (data[direction].nackCount || 0) + keys.reduce((sum, k) => (sum + (data[k] || 0)), 0);
}
</script>

<div class="rtc-conversation__options">
  <h3>{l('General')}</h3>
  <dl>
    <dt>{l(humanConnectionCatetory[connectionState[1]])}</dt>
    <dd>{l(ucFirst(connectionState[2]))}</dd>
    <dt>{l('Data')}</dt>
    <dd>{bytes(info.bytesReceived)}&#8659; {bytes(info.bytesSent)}&#8657;</dd>
    <dt>{l('Remote address')}</dt>
    <dd>{info.remoteAddress || '0.0.0.0'}</dd>
    <dt>{l('Local address')}</dt>
    <dd>{info.localAddress || '0.0.0.0'}</dd>
  </dl>

  {#if $rtc.constraints.video}
    <h3>{l('Video')}</h3>
    <dl>
      <dt>{l('Invalid packets')}</dt>
      <dd>{loss($conn, 'video', 'inbound')}&#8659; {loss($conn, 'video', 'outbound')}&#8657;</dd>
      <dt>{l('Jitter')}</dt>
      <dd>{info.video.jitter}</dd>
      <dt>{l('Framerate')}</dt>
      <dd>{framerate($conn, 'video', 'inbound')}&#8659; {framerate($conn, 'video', 'outbound')}&#8657;</dd>
    </dl>
  {/if}

  <h3>{l('Audio')}</h3>
  <dl>
    <dt>{l('Invalid packets')}</dt>
    <dd>{loss($conn, 'audio', 'inbound')}&#8659; {loss($conn, 'audio', 'outbound')}&#8657;</dd>
    <dt>{l('Jitter')}</dt>
    <dd>{info.audio.jitter}</dd>
  </dl>

  <div class="fake-padding-bottom">&nbsp;</div>
</div>
