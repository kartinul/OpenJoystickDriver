# #38: input wrongly mapped issue with PS3/PC Gamepad

> External GitHub snapshot. GitHub is authoritative if this file is stale.

- **Repository:** `xsyetopz/OpenJoystickDriver`
- **Source:** https://github.com/xsyetopz/OpenJoystickDriver/issues/38
- **State:** OPEN
- **Author:** kartinul
- **Created:** 2026-09-18T17:46:19Z
- **Updated:** 2026-09-24T02:07:33Z
- **Closed:** —
- **Labels:** —

## Report

PS3/PC Gamepad
Vendor: 2563 Product: 0575

left joystick ->
- going -ve x, showing -ve x
- going +ve x, showing -1 exactly
- going -ve y, showing 1 exactly
- going +ve y, showing +ve y

similar problem with right joystick,
+ many other buttons mismatchd

## Comments

### xsyetopz — 2026-09-18T21:19:22Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5736314943)

> PS3/PC Gamepad
> Vendor: 2563 Product: 0575
>
> left joystick ->
> - going -ve x, showing -ve x
> - going +ve x, showing -1 exactly
> - going -ve y, showing 1 exactly
> - going +ve y, showing +ve y
>
> similar problem with right joystick,
> + many other buttons mismatchd
>

I have found that my temporary DS4 (Sony DUALSHOCK 4 Controller) seems to inherit a similar issue on SDL2-3 mode with joysticks, and same for my GameSir-G7 SE

I'll have to take a look into this. My testing ground is PCSX2.

### xsyetopz — 2026-09-18T22:48:09Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5737099134)

<img width="3530" height="2392" alt="Image" src="https://github.com/user-attachments/assets/d832067b-8aeb-4f32-a5a2-3a8286752f31" />

On my way! I bought this.

### kartinul — 2026-09-20T09:00:42Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5748821075)

okay, thanks for confirming... i have mapped the raw bytes with the related bits for when my controller's buttons are pressed (if button) or mapped bytes to numeric bits (axis) for axis based...

here's the python file iv used to map along with the mappings. hope this helps.
id love to contribute more but since i dont got the apple devloper thing im unable to test and contribute

also if possible if you could export a easy way of creating a virtual controller via some scripting would love it... like id loved to use some api that lets me connect with ur driver to simulate an xbox controller of my own using the configs below

hope this is helpful!

[pad_config.json](https://github.com/user-attachments/files/32431750/pad_config.json)
[probe.py](https://github.com/user-attachments/files/32431751/probe.py)

### xsyetopz — 2026-09-20T09:10:09Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5748866443)

> also if possible if you could export a easy way of creating a virtual controller via some scripting would love it... like id loved to use some api that lets me connect with ur driver to simulate an xbox controller of my own using the configs below
>

Yes, so I've got a whole new to (hopefully) 'fix' the architecture, which currently on Beta.5 seems brittle, too. It means there will be more than just a few backends that only some controllers use, and a few for almost all of them.

Your idea for an SDK/API of sorts sounds actually really good. That is genuinely somethng useful. I'll see.

### kartinul — 2026-09-20T11:34:30Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5749538691)

okay then thanks for being so quick with it! waiting for the beta release to try it out

### xsyetopz — 2026-09-22T00:58:55Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5769739717)

> okay then thanks for being so quick with it! waiting for the beta release to try it out

I won't be working on it so far until the device actually appears in my hands and I get to actually take my time making sure not only the architecture gets resolved, but the new 2 controllers, and possible derivatives, work on them.

I now own, but haven't gotten hands on yet due to shipping, the next 2 controllers:

Sony DUALSHOCK 3 Wireless
Razer Wolverine Tournment Edition (V1, not V2 or V3!)

Both for less than 11 bucks each, and fully functional according to sellers.

I also own an official 2010/2011 Microsoft Xbox 360 Wireless controller, but I don't have the Wireless RF receiver, and I ordered one *months* ago, but never arrived...

### kartinul — 2026-09-23T18:50:10Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5800901710)

oh alright. if you want me to test it on my controller let me know... id be willing to run it for testing

also i already have attached a map of my controller to the raw input bytes in one of the above msgs because nothing was able to detect it... not even steam, nor pygame... but for some reason stardew valley detcted half of the controller correctly...

but whatever i'll be willing to test if needed

### xsyetopz — 2026-09-24T02:06:29Z

[Source comment](https://github.com/xsyetopz/OpenJoystickDriver/issues/38#issuecomment-5806176836)

> oh alright. if you want me to test it on my controller let me know... id be willing to run it for testing
>
> also i already have attached a map of my controller to the raw input bytes in one of the above msgs because nothing was able to detect it... not even steam, nor pygame... but for some reason stardew valley detcted half of the controller correctly...
>
> but whatever i'll be willing to test if needed

BIG UPDATE: Not only did I get 2 genuine C1-based controllers now, (early Sixaxis--no rumble!) but I happen to have found, bought, and own a fat PS3 from 2008, and I homebrewed it yesterday. So, I got 2 genuines and a fake PS3 controller, and I can use the PS3 to let a reverse-engineering agent actually start capturing packets and other useful data from the console *to* the Mac for maximum accuracy in Sony's proprietary DS3 protocol, since fakes don't and can't use it.
