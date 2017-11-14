import computed from 'ember-addons/ember-computed-decorators';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Component.extend({
  disabled: Ember.computed.or('unchanged', 'saving', 'invalid'),

  @computed('property', 'name')
  unchanged(current, name) {
    const original = this.get(`topic.election_${name}`);
    return current === original;
  },

  prepareData() {
    if (this.get(`disabled`)) return false;

    this.setProperties({
      icon: null,
      saving: true
    });
    $('#modal-alert').hide();

    const property = this.get('property');
    const name = this.get('name');
    const topicId = this.get('topic.id');
    let data = { topic_id: topicId };

    data[name] = property;

    return data;
  },

  resolve(result) {
    const property = this.get('property');
    const name = this.get('name');
    const original = this.get(`topic.election_${name}`);

    if (result.success) {
      this.set('icon', 'check');
      this.set(`topic.election_${name}`, property);
    } else if (result.failed) {
      this.setProperties({
        icon: 'times',
        property: original
      });
      this.sendAction('error', result.message);
    }

    this.sendAction('saved');
    this.set('saving', false);
  },

  resolveStandardError(responseText) {
    const message = responseText.substring(responseText.indexOf('>'), responseText.indexOf('----'));
    this.resolve({ failed: true, message });
  },

  actions: {
    save() {
      if (this.get('usernamesSelector')) return this.send('usernamesSave');

      const data = this.prepareData();
      const name = this.get('name');
      if (!data) return;

      ajax(`/election/set-${name.dasherize()}`, { type: 'PUT', data }).then((result) => {
        this.resolve(result);
      }).catch((e) => {
        if (e.jqXHR && e.jqXHR.responseText) {
          this.resolveStandardError(e.jqXHR.responseText);
        }
      }).finally(() => this.resolve({}));
    },

    usernamesSave() {
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
