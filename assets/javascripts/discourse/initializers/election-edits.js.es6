import { iconNode } from 'discourse/helpers/fa-icon-node';
import { withPluginApi } from 'discourse/lib/plugin-api';
import { escapeExpression } from 'discourse/lib/utilities';
import RawHtml from 'discourse/widgets/raw-html';

export default {
  name: 'election-edits',
  initialize() {
    withPluginApi('0.8.7', api => {
      api.reopenWidget('discourse-poll-option', {
        html(attrs) {
          let result = [];

          const { option, vote } = attrs;
          const chosen = vote.indexOf(option.id) !== -1;

          if (attrs.isMultiple) {
            result.push(iconNode(chosen ? 'check-square-o' : 'square-o'));
          } else {
            result.push(iconNode(chosen ? 'dot-circle-o' : 'circle-o'));
          }
          result.push(' ');
          result.push(new RawHtml({ html: `${_.unescape(option.html)}` }));

          return result;
        }
      })

      api.decorateWidget('post-contents:after-cooked', (helper) => {
        const user = helper.widget.currentUser;
        if (!user) return;

        const post = helper.widget.parentWidget.parentWidget.parentWidget.model;
        const topic = post.topic;
        if (!topic.closed && post.post_number === 1) {
          return helper.attach('election-controls', { topic });
        }
      })
    })

    function description() {
      const data = this.attrs.data;
      const badgeName = data.badge_name;
      if (badgeName) return escapeExpression(badgeName);

      const description = data.description;
      if (description) return escapeExpression(description);

      const title = data.topic_title;
      return Ember.isEmpty(title) ? "" : escapeExpression(title);
    }

    withPluginApi('0.5', api => {
      api.reopenWidget('notification-item', { description });
    })
  }
}
