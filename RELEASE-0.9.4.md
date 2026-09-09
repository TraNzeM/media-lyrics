# media-lyrics 0.9.4 — release notes & issue #649

## Release note (EN)

> **Fix: marquee text no longer blinks through panel transparency**
>
> When a long title or artist scrolled (marquee), the panel recreated the text node on every frame by embedding the current slice into the node key. Under compositor blur/transparency this forced a full surface re-blur each frame, causing the text to visibly blink while scrolling (static text was unaffected).
>
> The marquee node now uses a stable key and only its text is updated in place, so the surface is no longer recreated per frame. Scrolling is smooth and respects the compositor's transparency rules.

## Release note (RU)

> **Исправление: текст маркизы больше не мигает сквозь прозрачность панели**
>
> Когда длинный заголовок или исполнитель прокручивался (маркиза), панель пересоздавала текстовый узел на каждом кадре, встраивая текущий срез текста в ключ узла. При блюре/прозрачности композитора это заставляло полностью пере-блюривать поверхность каждый кадр, из-за чего текст заметно мигал при прокрутке (статичный текст не затрагивался).
>
> Теперь узел маркизы использует стабильный ключ, и обновляется только его текст на месте — поверхность больше не пересоздаётся каждый кадр. Прокрутка плавная и уважает правила прозрачности композитора.

---

## Issue #649 comment (EN)

> I tested this on my setup and applied a fix for a likely root cause, though I couldn't reproduce the blink myself to confirm it.
>
> What I tested: Niri 26.04, Noctalia v5, media-lyrics 0.9.3, Intel Crystal Well iGPU (i915), Arch Linux. I tried the panel at Compact and Medium sizes with a long title and artist (both fields scrolling), across every transparency combination — host `transparency_mode` solid/soft/glass, compositor `layer-rule` opacity 0.3/0.6/0.9, blur on/off, xray true/false, and an aggressive global blur (passes 4, offset 6). In all cases the marquee scrolled smoothly with no blink.
>
> The likely cause: the marquee recreated the text node every frame by putting the current slice into the node key (`key = key .. "-" .. shown`). Under compositor blur this re-dirties the surface each frame, so the compositor re-blurs it and the text blinks. I changed it to a stable key so only the text updates in place. This should fix the blink on AMD too, but I couldn't verify it here since my iGPU doesn't reproduce it.
>
> This fix will be included starting with version 0.9.4.

## Issue #649 comment (RU)

> Я протестировал на своей системе и внёс исправление вероятной первопричины, хотя сам мигание воспроизвести не смог, чтобы подтвердить.
>
> Что тестировал: Niri 26.04, Noctalia v5, media-lyrics 0.9.3, Intel Crystal Well iGPU (i915), Arch Linux. Пробовал панель в размерах Compact и Medium с длинным заголовком и исполнителем (оба поля скроллятся), через все комбинации прозрачности — `transparency_mode` хоста solid/soft/glass, `layer-rule` композитора opacity 0.3/0.6/0.9, блюр вкл/выкл, xray true/false, и агрессивный глобальный блюр (passes 4, offset 6). Во всех случаях маркиза скроллилась плавно, без мигания.
>
> Вероятная причина: маркиза пересоздавала текстовый узел каждый кадр, встраивая текущий срез в ключ узла (`key = key .. "-" .. shown`). При блюре композитора это пере-грязнит поверхность каждый кадр, композитор пере-блюривает её, и текст мигает. Я заменил на стабильный ключ, чтобы обновлялся только текст на месте. Это должно исправить мигание и на AMD, но здесь я проверить не смог, так как мой iGPU его не воспроизводит.
>
> Это исправление будет включено начиная с версии 0.9.4.
