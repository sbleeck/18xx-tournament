# frozen_string_literal: true

module Lib
  module CardAnimation
    def self.fly(source_selector, dest_selector, &block)
      %x{
        var js_block = #{block};
        var card = null, startX, startY, width, height, clone, styleEl;
        try {
          var sel = #{source_selector};
          card = window.document.querySelector(sel);
          if (!card) {
            var parts = sel.split(' ');
            var id = parts[0].replace('#', '');
            var parent = window.document.getElementById(id);
            if (parent) {
              card = parent.querySelector('.game-card') || parent.querySelector('.card') || parent;
            }
          }
        } catch(e) {
          console.warn("Animation failed to locate source: " + #{source_selector}, e);
        }

        if (!card) {
          if (js_block) {
            js_block.$call();
          }
          return;
        }

        var rect = card.getBoundingClientRect();
        startX = rect.left;
        startY = rect.top;
        width = rect.width;
        height = rect.height;

        clone = card.cloneNode(true);

        var nestedDivs = clone.getElementsByTagName('div');
        for (var i = 0; i < nestedDivs.length; i++) {
          if (nestedDivs[i].style.position === 'absolute') {
            nestedDivs[i].parentNode.removeChild(nestedDivs[i]);
          }
        }

        clone.style.position = 'fixed';
        clone.style.left = startX + 'px';
        clone.style.top = startY + 'px';
        clone.style.width = width + 'px';
        clone.style.height = height + 'px';
        clone.style.zIndex = '9999';
        clone.style.margin = '0';
        clone.style.transition = 'transform 0.5s ease-in-out, opacity 0.5s ease-in-out';
        clone.style.pointerEvents = 'none';

        window.document.body.appendChild(clone);

        styleEl = window.document.createElement('style');
        styleEl.innerHTML = #{source_selector} + " { opacity: 0 !important; pointer-events: none !important; }";
        window.document.head.appendChild(styleEl);

        window.requestAnimationFrame(function() {
          window.requestAnimationFrame(function() {
            var dest = window.document.querySelector(#{dest_selector});
            if (dest) {
              var destRect = dest.getBoundingClientRect();
              var destX = destRect.left + (destRect.width / 2) - (width / 2);
              var destY = destRect.top + (destRect.height / 2) - (height / 2);

              clone.style.transform = 'translate(' + (destX - startX) + 'px, ' + (destY - startY) + 'px)';
            } else {
              clone.style.transform = 'translate(0px, -50px) scale(1.1)';
              clone.style.opacity = '0';
            }

            setTimeout(function() {
              if (js_block) {
                js_block.$call();
              }

              setTimeout(function() {
                clone.style.transition = 'opacity 0.2s ease-out';
                clone.style.opacity = '0';

                setTimeout(function() {
                  if (clone.parentNode) {
                    clone.parentNode.removeChild(clone);
                  }
                  if (styleEl && styleEl.parentNode) {
                    styleEl.parentNode.removeChild(styleEl);
                  }
                }, 200);
              }, 100);
            }, 500);
          });
        });
      }
    end
  end
end
