import { withPluginApi } from 'discourse/lib/plugin-api';
import { escapeExpression } from 'discourse/lib/utilities';
import Composer from 'discourse/models/composer';
import { ElectionStatuses } from '../lib/election';
import RawHtml from 'discourse/widgets/raw-html';
import { default as computed } from 'ember-addons/ember-computed-decorators';
import { h } from 'virtual-dom';

export default {
  name: 'election-edits',
  initialize(container) {
    const siteSettings = container.lookup('site-settings:main');
    if (siteSettings.elections_enabled) {

      withPluginApi('0.8.7', api => {
        api.modifyClass('model:topic', {
          @computed('election_status')
          electionStatusName(status) {
            return Object.keys(ElectionStatuses).find((k) => {
              return ElectionStatuses[k] === status;
            });
          }
        });

        api.modifyClass('model:composer', {
          @computed('electionNominationStatement', 'post.election_nomination_statement', 'topic.election_is_nominee')
          isNominationStatement(newStatement, existingStatement, isNominee) {
            return (newStatement || existingStatement) && isNominee;
          }
        });

        api.reopenWidget('discourse-poll-container', {
          html(attrs) {
            const { poll } = attrs;
            const options = poll.get('options');

            options.forEach((o) => {
              if (!o.originalHtml) {
                o.originalHtml = o.html;
              }
              o.html = o.originalHtml;
              let usernameOnly = o.html.substring(0, o.html.indexOf('<'));
              let fullDetails = o.html.replace(usernameOnly, '');
              o.html = attrs.showResults ? usernameOnly : fullDetails;
            });

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

        api.includePostAttributes("topic",
                                  "election_post",
                                  "election_nomination_statement",
                                  "election_nominee_title",
                                  "election_by_nominee");

        api.addPostClassesCallback((attrs) => {
          if (attrs.election_post) return ["election-post"];
        });

        api.decorateWidget('poster-name:after', (helper) => {
          const post = helper.attrs;
          let contents = [];

          if (post.election_by_nominee && post.election_nomination_statement) {
            contents.push(helper.h('span.statement-post-label', I18n.t('election.post.nomination_statement')));
          }

          if (!post.election_by_nominee && post.election_nominee_title && Discourse.SiteSettings.elections_nominee_titles) {
            contents.push(helper.h('span.nominee-title',
              new RawHtml({ html: post.election_nominee_title })
            ));
          }

          return contents;
        });

        api.decorateWidget('post-avatar:after', (helper) => {
          const post = helper.attrs;
          const flair = Discourse.SiteSettings.elections_nominee_avatar_flair;
          let contents = [];

          if (post.election_by_nominee && flair.length > 0) {
            contents.push(helper.h('div.avatar-flair.nominee', helper.h('i', {
              className: 'fa ' + flair,
              title: I18n.t('election.post.nominee'),
            })));
          }

          return contents;
        });

        api.decorateWidget('post-contents:after-cooked', (helper) => {
          const post = helper.attrs;
          const topic = post.topic;
          if (topic.subtype === 'election' && post.firstPost) {
            return helper.attach('election-controls', { topic });
          }
        });

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
      });

      Composer.serializeOnCreate('election_nomination_statement', 'electionNominationStatement');
    }
  }
};
