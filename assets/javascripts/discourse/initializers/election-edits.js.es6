import { iconNode } from 'discourse/helpers/fa-icon-node';
import { withPluginApi } from 'discourse/lib/plugin-api';
import { escapeExpression } from 'discourse/lib/utilities';
import Composer from 'discourse/models/composer';
import RawHtml from 'discourse/widgets/raw-html';
import { default as computed } from 'ember-addons/ember-computed-decorators';
import evenRound from "discourse/plugins/poll/lib/even-round";
import { h } from 'virtual-dom';

export default {
  name: 'election-edits',
  initialize(container) {
    Composer.serializeOnCreate('election_nomination_statement', 'electionNominationStatement')

    Composer.reopen({
      electionNominationStatement: Ember.computed.alias('election_nomination_statement')
    })

    withPluginApi('0.8.7', api => {
      api.reopenWidget('discourse-poll-container', {
        html(attrs) {
          const { poll } = attrs;
          const options = poll.get('options');

          options.forEach((o) => {
            if (!o.originalHtml) {
              o.originalHtml = o.html
            }
            o.html = o.originalHtml;
            let usernameOnly = o.html.substring(0, o.html.indexOf('<'));
            let fullDetails = o.html.replace(usernameOnly, '');
            o.html = attrs.showResults ? usernameOnly : fullDetails;
          })

          if (attrs.showResults) {
            const type = poll.get('type') === 'number' ? 'number' : 'standard';
            return this.attach(`discourse-poll-${type}-results`, attrs);
          }

          if (options) {
            return h('ul', options.map(option => {
              return this.attach('discourse-poll-option', {
                option,
                isMultiple: attrs.isMultiple,
                vote: attrs.vote
              });
            }));
          }
        }
      });

      api.includePostAttributes('election_post')

      api.addPostClassesCallback((attrs) => {
        if (attrs.election_post) return ["election-post"];
      })

      api.decorateWidget('post-meta-data:after', (helper) => {
        const post = helper.widget.parentWidget.parentWidget.parentWidget.model;
        if (post.election_is_nominee) {
          return helper.h('span.nominated', I18n.t('election.post.nominated'))
        }
      })

      api.decorateWidget('post-contents:after-cooked', (helper) => {
        const user = helper.widget.currentUser;
        if (!user) return;

        const post = helper.widget.parentWidget.parentWidget.parentWidget.model;
        const topic = post.topic;
        if (!topic.closed && topic.subtype === 'election' && post.post_number === 1) {
          return helper.attach('election-controls', { topic });
        }
      })

      api.reopenWidget('notification-item', {
        description() {
          const data = this.attrs.data;
          const badgeName = data.badge_name;
          if (badgeName) return escapeExpression(badgeName);

          const description = data.description;
          if (description) return escapeExpression(description);

          const title = data.topic_title;
          return Ember.isEmpty(title) ? "" : escapeExpression(title);
        }
      });
    })
  }
}
