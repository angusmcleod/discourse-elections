import { default as computed } from 'ember-addons/ember-computed-decorators';
import DiscourseURL from 'discourse/lib/url';

const electionStatus = {
  1: 'nomination',
  2: 'poll',
  3: 'closed_poll'
};

export default Ember.Component.extend({
  classNameBindings: [':election-banner', 'statusClass'],

  @computed('election.status')
  status: (status) => electionStatus[status],

  @computed('status')
  statusClass: (status) => `election-${status.dasherize()}`,

  @computed('status')
  key: (status) => `election.status_banner.${status}`,

  @computed('status')
  timeKey: (status) => `election.status_banner.${status}_time`,

  click() {
    const topicUrl = this.get('election.topic_url');
    DiscourseURL.routeTo(topicUrl);
  }
});
