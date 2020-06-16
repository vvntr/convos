<script>
import {getContext, onMount} from 'svelte';

export let conn;
export let rtc;

const user = getContext('user');

$: cameras = $rtc.cameras;
$: microphones = $rtc.microphones;
$: speakers = $rtc.speakers;

onMount(() => conn.getDevices()); // Using "conn" to avoid "cal has unused export property 'conn'" warning

function changeDevice(e) {
  const input = e.target.closest('input');
  $rtc.setDevice(input.name, input.value).catch(err => user.embedMaker.alert(err.message || String(err)));
}
</script>

<div class="rtc-conversation__options">
  <form on:change="{changeDevice}">
    {#if $rtc.constraints.video && cameras.length}
      <h4>Camera</h4>
      {#each cameras as dev}
        <label class="radio">
          <input type="radio" name="camera" value="{dev.id}" checked="{dev.active}">
          <span>{dev.name}</span>
        </label>
      {/each}
    {/if}

    {#if microphones.length}
      <h4>Microphone</h4>
      {#each microphones as dev}
        <label class="radio">
          <input type="radio" name="microphone" value="{dev.id}" checked="{dev.active}">
          <span>{dev.name}</span>
        </label>
      {/each}
    {/if}

    {#if speakers.length}
      <h4>Speaker</h4>
      {#each speakers as dev}
        <label class="radio">
          <input type="radio" name="speaker" value="{dev.id}" checked="{dev.active}">
          <span>{dev.name}</span>
        </label>
      {/each}
    {/if}
  </form>

  <div class="fake-padding-bottom">&nbsp;</div>
</div>
