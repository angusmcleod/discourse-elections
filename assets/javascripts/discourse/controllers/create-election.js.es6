import { default as computed } from 'ember-addons/ember-computed-decorators';
import DiscourseURL from 'discourse/lib/url';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Controller.extend({
  emojiPickerIsActive: false,

  @computed('position')
  disabled(position) {
    return !position;
  },

  actions: {
    createElection() {
      const data = {
        category_id: this.get('model.categoryId'),
        position: this.get('position'),
        details_url: this.get('detailsUrl'),
        message: this.get('message')
      };

      this.set('loading', true);
      ajax(`/election/create`, {type: 'POST', data}).then((result) => {
        this.set('loading', false);

        if (result.topic_url) {
          DiscourseURL.routeTo(result.topic_url);
        }
      })
    }
  }
})
