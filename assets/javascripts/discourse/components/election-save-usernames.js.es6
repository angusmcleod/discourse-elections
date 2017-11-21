import ElectionSave from './election-save';
import { ajax } from 'discourse/lib/ajax';

export default ElectionSave.extend({
  layoutName: 'components/election-save',

  actions: {
    save() {
      const data = this.prepareData();
      if (!data) return;

      const handleFail = () => {
        const existing = this.get('topic.election_nominations_usernames');
        this.set('usernamesString', existing.join(','));

        // this is hack to get around stack overflow issues with user-selector's canReceiveUpdates property
        this.set('showSelector', false);
        Ember.run.scheduleOnce('afterRender', this, () => this.set('showSelector', true));
      };

      ajax('/election/nomination/set-by-username', { type: 'POST', data }).then((result) => {
        this.resolve(result, 'usernames');

        if (result.failed) {
          handleFail();
        } else {
          this.set('topic.election_nominations', result.user_ids);
          this.set('topic.election_nominations_usernames', result.usernames);
          this.set('topic.election_is_nominee', result.user_ids.indexOf(this.currentUser.id) > -1);
        }
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          this.resolveStandardError(e.jqXHR.responseText, 'usernames');
          handleFail();
        }
      }).finally(() => this.resolve({}, 'usernames'));
    }
  }
});
