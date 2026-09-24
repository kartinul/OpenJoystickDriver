# #32: .5 beta 3 appears to break OG wired xbox 360 support

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/32
- **State:** OPEN
- **Author:** Jottle
- **Created:** 2026-09-06T16:44:57Z
- **Updated:** 2026-09-22T15:49:25Z
- **Closed:** —
- **Labels:** —

## Report

Looks like something went wrong with the latest release. This controller was working in beta 2. OJD recognizes the controller in beta 3 (as shown in dropdown), lighted controller ring lights up correctly, but the input tester doesn't register any button presses. I tried using the controller in a game, and it's not registering.

<img width="382" height="198" alt="Image" src="https://github.com/user-attachments/assets/20f7d538-4e81-4c34-bc12-463931ae484d" />

## Comments

### Jottle — 2026-09-06T16:49:43Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5560698227)

Weird. It seems to be working in the input tester again for some reason, which is why I closed the issue. But the controller is not registering in-game for steam games.

### xsyetopz — 2026-09-06T18:02:44Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5561106050)

Reopening issue just to see what went wrong.

### xsyetopz — 2026-09-15T00:32:51Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5672842939)

OpenJoystickDriver 0.5.0-beta.4 is published: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4

This release replaces the virtual-output lifecycle path and clears stale controller state before a new physical session. Please retest the original wired Xbox 360 controller in both the input tester and Steam, including disconnect and reconnect.

Keeping this issue open until the signed release is confirmed on the reported hardware.

### Jottle — 2026-09-18T17:52:34Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5734008984)

> OpenJoystickDriver 0.5.0-beta.4 is published: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4
>
> This release replaces the virtual-output lifecycle path and clears stale controller state before a new physical session. Please retest the original wired Xbox 360 controller in both the input tester and Steam, including disconnect and reconnect.
>
> Keeping this issue open until the signed release is confirmed on the reported hardware.

It's weird now. Still not working correctly. When connecting the controller, OJD recognized the controller being connected (identified as "controller, xbox 360 wired). Input test and lights were all non-funcational on the OJD input test. But when I open up steam, OJD registered the same controller again in OJD as a second controller called "Gamepad-1." But it keeps connecting and disconnecting over and over again in OJD every 10 seconds, almost like it's conflicting with the steam driver. But while it's connected as "gamepad-1", the "controller" profile becomes active and the OJD input test works. But in steam games, the controller is unresponsive.

Is there a console log I can send you?

<img width="897" height="635" alt="Image" src="https://github.com/user-attachments/assets/5ca9905e-3f26-40a2-8b37-2c1bc9211a6c" />

### xsyetopz — 2026-09-18T21:17:34Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5736298033)

> > OpenJoystickDriver 0.5.0-beta.4 is published: https://github.com/xsyetopz/OpenJoystickDriver/releases/tag/0.5.0-beta.4
> >
> > This release replaces the virtual-output lifecycle path and clears stale controller state before a new physical session. Please retest the original wired Xbox 360 controller in both the input tester and Steam, including disconnect and reconnect.
> >
> > Keeping this issue open until the signed release is confirmed on the reported hardware.
>
> It's weird now. Still not working correctly. When connecting the controller, OJD recognized the controller being connected (identified as "controller, xbox 360 wired). Input test and lights were all non-funcational on the OJD input test. But when I open up steam, OJD registered the same controller again in OJD as a second controller called "Gamepad-1." But it keeps connecting and disconnecting over and over again in OJD every 10 seconds, almost like it's conflicting with the steam driver. But while it's connected as "gamepad-1", the "controller" profile becomes active and the OJD input test works. But in steam games, the controller is unresponsive.
>
> Is there a console log I can send you?
>
> <img width="897" height="635" alt="Image" src="https://github.com/user-attachments/assets/5ca9905e-3f26-40a2-8b37-2c1bc9211a6c" />

In Settings tab, there is a toggle for Developer Tools, then you can access the raw packet output and paste it here, or provide a pastebin if it's too large.

### Jottle — 2026-09-21T00:28:39Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5753875548)

Steam is now actually recognizing the controller in a stable way, (not connecting and disconnecting over and over again), and I can actually use the input tester in steam successfully to recognize all the buttons. Not sure what changed, but it's currently functioning again, at least with steam.

### xsyetopz — 2026-09-21T00:44:40Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5753968626)

> Steam is now actually recognizing the controller in a stable way, (not connecting and disconnecting over and over again), and I can actually use the input tester in steam successfully to recognize all the buttons. Not sure what changed, but it's currently functioning again, at least with steam.

Is it on the latest beta.5, or...? If you look at the about-me, what does it say?

### Jottle — 2026-09-21T00:54:27Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5754025025)

Yes. **This is for beta .4** What happens is opening up steam makes the controller be recognized (though it shows a different controller profile in OJD when steam is open, "gamepad-1" is that duplicate that works). Then, when I close down steam, the controller reverts the original controller name in OJD, "Controller," and it continues to work and be recognized in the OJD input tester after steam is closed.
But(!), if I then disconnect the controller and reconnect it physically, it again goes back to the inputs not being recognized or working until I open up steam again.

### xsyetopz — 2026-09-21T00:56:12Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5754035315)

> Yes. **This is for beta .4** What happens is opening up steam makes the controller be recognized (though it shows a different controller profile in OJD when steam is open, "gamepad-1" is that duplicate that works). Then, when I close down steam, the controller reverts the original controller name in OJD, "Controller," and it continues to work and be recognized in the OJD input tester after steam is closed. But(!), if I then disconnect the controller and reconnect it physically, it again goes back to the inputs not being recognized or working until I open up steam again.

What about current Beta.5 branch?

### Jottle — 2026-09-21T01:30:56Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5754253943)

Can you link me to beta .5? I can't find it.

### xsyetopz — 2026-09-21T01:33:38Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5754273687)

> Can you link me to beta .5? I can't find it.

https://github.com/xsyetopz/OpenJoystickDriver/tree/feat/0.5.0-beta.5

### Jottle — 2026-09-21T04:16:00Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5755305337)

> > Can you link me to beta .5? I can't find it.
>
> https://github.com/xsyetopz/OpenJoystickDriver/tree/feat/0.5.0-beta.5

Thanks, but I can't compile it on my own. Do you have an intel version?

### xsyetopz — 2026-09-21T04:17:31Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5755316409)

> > > Can you link me to beta .5? I can't find it.
> >
> >
> > https://github.com/xsyetopz/OpenJoystickDriver/tree/feat/0.5.0-beta.5
>
> Thanks, but I can't compile it on my own. Do you have an intel version?

It should be a Universal binary. Do you want me to create a tester build? I could share it on Discord since that's where i dump my builds to, so we don't pollute the discussionary.

### Jottle — 2026-09-22T15:49:25Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/32#issuecomment-5779564206)

> > > > Can you link me to beta .5? I can't find it.
> > >
> > >
> > > https://github.com/xsyetopz/OpenJoystickDriver/tree/feat/0.5.0-beta.5
> >
> >
> > Thanks, but I can't compile it on my own. Do you have an intel version?
>
> It should be a Universal binary. Do you want me to create a tester build? I could share it on Discord since that's where i dump my builds to, so we don't pollute the discussionary.

I'm not super familiar with github. I don't see how to download the .5 beta as a universal binary. I just see up to beta .4 in the "releases" section. Sorry.
