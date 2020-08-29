<script>
import Button from './components/form/Button.svelte';
import TextField from './components/form/TextField.svelte';
import VideoStream from './components/VideoStream.svelte';
import WebRTC from './store/WebRTC';
import {getSocket} from './js/Socket';
import {l} from './js/i18n';
import {onMount} from 'svelte';
import {settings, viewport} from './store/Viewport';
import {route} from './store/Route';

route.update({baseUrl: settings('base_url')});

const dialogName = settings('dialog_name');
const rtc = new WebRTC({});
const videoStreamCssRule = getCSSRule('.video-stream');
const socket = getSocket('video');

let name = route.param('name');
let loadingState = 'pending';

$: streams = $rtc.allActiveStreams();
$: calculateFlexStyle(streams.length);

onMount(() => {
  socket.update({url: route.wsUrlFor(route.path)});
  if (route.param('join')) join({});
});

function calculateFlexStyle(nStreams) {
  const three = nStreams % 3;
  const four = nStreams % 4;
  const basis
    = nStreams <= 4 ? (100 / nStreams)
    : !three && four || four == 1 ? (100 / 3)
    : (100 / 4);

  videoStreamCssRule.style.flexBasis = basis + '%';
}

function getCSSRule(ruleName) {
  let rule = null;
  [].find.call(document.styleSheets, styleSheet => {
    return [].find.call(styleSheet.cssRules, cssRule => {
      return cssRule.selectorText && cssRule.selectorText.toLowerCase() == ruleName ? (rule = cssRule) : null;
    });
  });
  return rule;
}

function join(e) {
  if (e.preventDefault) e.preventDefault();
  loadingState = 'loading';
  socket.send({method: 'rtc', action: 'join', name});
  rtc.call();
}
</script>

<main class="convos-video-chat is-{loadingState}">
  {#if loadingState == 'pending'}
    <h1>{l('Video chat with %1', dialogName)}</h1>

    <p>{l('Enter your name and join the conversation.')}</p>
    <form on:submit="{join}">
      <div class="inputs-side-by-side">
        <TextField name="name" bind:value="{name}">
          <span slot="label">{l('Your name')}</span>
        </TextField>
        <div class="has-remaining-space">
          <Button type="button" icon="comment" on:click="{join}" disabled="{!name}"><span>{l('Join')}</span></Button>
        </div>
      </div>
      <p class="text-center"><small>{l('Currently %1 participants in %2.', 2, dialogName)}</p>
    </form>
  {/if}

  {#if loadingState != 'pending' && streams.length}
    <div class="video-stream-container has-{streams.length > 2 ? 'many' : 'few'}-streams">
      {#each streams as stream}
        <VideoStream name="{name}" rtc="{$rtc}" stream="{stream}"/>
      {/each}
    </div>
    <div class="local-video-stream-actions">
      <Button type="button" icon="comment" on:click="{join}" disabled="{!name}"><span>{l('Join')}</span></Button>
    </div>
  {/if}
</main>
