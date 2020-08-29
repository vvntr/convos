<script>
import Icon from './Icon.svelte';

export let name = 'Guest';
export let rtc;
export let stream;

let readyState = 0;
let videoEl;

$: if (videoEl) renderVideoEl(videoEl);
$: isLocal = stream == rtc.localStream;
$: classNames = ['video-stream', 'has-state-' + readyState, (isLocal ? 'is-local' : 'is-remote')];

function renderVideoEl(videoEl) {
  if (videoEl.srcObject) return;
  videoEl.setAttribute('autoplay', '');
  videoEl.setAttribute('playsinline', '');
  videoEl.height = parseInt(rtc.videoQuality.split('x')[1], 10);
  videoEl.width = parseInt(rtc.videoQuality.split('x')[0], 10);
  videoEl.oncanplay = () => { readyState =  videoEl.readyState };
  videoEl.srcObject = stream;
}
</script>

<div class="{classNames.join(' ')}">
  <video bind:this="{videoEl}"/>
  <div class="rtc-conversation__actions">
    {#if $rtc.constraints.video}
      <button class="btn rtc-conversation__zoom"><i></i></button>
      <button class="btn rtc-conversation__mute-video"><i></i></button>
    {/if}
    <button class="btn rtc-conversation__hangup"><i></i></button>
    <button class="btn rtc-conversation__mute-audio"><i></i></button>
  </div>
  <span class="rtc-conversation__name"><Icon name="pick:{name}" family="solid"/> <span>{name}</span></span>
</div>
