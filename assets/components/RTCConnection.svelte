<script>
import Icon from '../components/Icon.svelte';
import RTCConnectionOptionsLocal from '../components/RTCConnectionOptionsLocal.svelte';
import RTCConnectionOptionsRemote from '../components/RTCConnectionOptionsRemote.svelte';
import {getContext, onDestroy, onMount} from 'svelte';
import {l} from '../js/i18n';

const user = getContext('user');

let connectionState = 'Unknown';
let isZoomed = false;
let optionsComponent = null;
let readyState = 0;
let tid;
let videoEl;
let videoSize = [640, 360];

export let conn;
export let dialog;
export let rtc;

$: connection = user.findDialog({connection_id: dialog.connection_id});
$: nick = conn.remoteStream ? conn.nick : $connection.nick;
$: hasVideo = $rtc.constraints.video && !$rtc.isMuted(nick, 'video') && readyState;
$: info = $conn.info;
$: isLocal = !conn.remoteStream;
$: wrapperClassNames = calculateWrapperClass($conn, {isZoomed, readyState});
$: if (videoEl) renderVideoEl(videoEl, $rtc);

function calculateWrapperClass(conn, {isZoomed, readyState}) {
  const names = ['rtc-conversation'];
  if (isZoomed) names.push('is-zoomed');
  names.push('is-' + (isLocal ? 'local' : 'remote'));
  names.push('has-state-' + readyState);
  names.push(rtc.constraints.video ? 'has-video' : 'has-audio-only');
  return names.join(' ');
}

function hangup(e) {
  rtc.hangup();
}

function renderVideoEl(el, rtc) {
  el.oncanplay = () => { readyState = videoEl.readyState };
  if (el.srcObject != conn.videoStream) el.srcObject = conn.videoStream;
  if (isLocal) [el.muted, el.volume] = [true, 0];
  if (conn.remoteStream) return;

  const speaker = rtc.speakers.filter(dev => dev.active)[0];
  if (speaker) el.setSink(speaker.id);
}

function toggleMute(e) {
  const btn = e.target.closest('.btn');
  const kind = btn.classList.contains('for-mute-audio') ? 'audio' : 'video';
  rtc.mute(nick, kind);
}

function toggleOptions(e) {
  e.preventDefault();
  optionsComponent = optionsComponent ? null : isLocal ? RTCConnectionOptionsLocal : RTCConnectionOptionsRemote;
}

function toggleZoom(e) {
  isZoomed = !isZoomed;
}
</script>

<div class="{wrapperClassNames}">
  <video width="{videoSize[0]}" height="{videoSize[1]}" autoplay playsinline bind:this="{videoEl}"></video>

  {#if optionsComponent}
    <svelte:component this="{optionsComponent}" conn="{conn}" rtc="{rtc}"/>
  {:else}
    <a href="#toggleOptions" class="rtc-conversation__name" class:is-over-video="{hasVideo}" on:click="{toggleOptions}" tabindex="0"><Icon name="pick:{nick}" family="solid"/> <span>{$connection.nick}</span></a>
  {/if}

  {#if isLocal}
    <div class="rtc-conversation__local-actions">
      <button class="btn for-mute-audio" class:is-active="{$rtc.isMuted(nick, 'audio')}" on:click="{toggleMute}"><i></i></button>
      <button class="btn for-hangup" on:click="{hangup}"><i></i></button>
      {#if $rtc.constraints.video}
        <button class="btn for-mute-video" class:is-active="{$rtc.isMuted(nick, 'video')}" on:click="{toggleMute}"><i></i></button>
      {/if}
    </div>
  {/if}

  <div class="rtc-conversation__generic-actions">
    <button class="btn for-zoom" on:click="{toggleZoom}" class:is-active="{isZoomed}"><i></i></button>
    <button class="btn for-options" on:click="{toggleOptions}" class:is-active="{!!optionsComponent}"><i></i></button>
  </div>
</div>
