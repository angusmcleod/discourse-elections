import { default as computed } from 'ember-addons/ember-computed-decorators';
import DiscourseURL from 'discourse/lib/url';
import { ajax } from 'discourse/lib/ajax';

export default Ember.Controller.extend({
  statusBannerResultHours: Discourse.SiteSettings.elections_status_banner_default_result_hours,
  statusBanner: true,
  pollOpenAfter: true,
  pollOpenAfterHours: 48,
  pollOpenAfterNominations: 2,
  pollCloseAfter: true,
  pollCloseAfterHours: 48,

  @computed('position', 'pollTimesValid')
  disabled(position, pollTimesValid) {
    return !position || position.length < 3 || !pollTimesValid;
  },

  @computed('pollOpenTime', 'pollCloseTime')
  pollTimesValid(pollOpenTime, pollCloseTime) {
    if (pollOpenTime && moment().isAfter(pollOpenTime)) return false;
    if (pollCloseTime && moment().isAfter(pollCloseTime)) return false;
    if (pollOpenTime && pollCloseTime && moment(pollCloseTime).isBefore(pollOpenTime)) return false;
    return true;
  },

  actions: {
    createElection() {
      let data = {
        category_id: this.get('model.categoryId'),
        position: this.get('position'),
        nomination_message: this.get('nominationMessage'),
        poll_message: this.get('pollMessage'),
        closed_poll_message: this.get('closedPollMessage'),
        self_nomination_allowed: this.get('selfNominationAllowed'),
        status_banner: this.get('statusBanner'),
        status_banner_result_hours: this.get('statusBannerResultHours'),
      };

      const pollOpen = this.get('pollOpen');
      data['poll_open'] = pollOpen;
      if (pollOpen) {
        const pollOpenAfter = this.get('pollOpenAfter');
        data['poll_open_after'] = pollOpenAfter;
        if (pollOpenAfter) {
          data['poll_open_after_hours'] = this.get('pollOpenAfterHours');
          data['poll_open_after_nominations'] = this.get('pollOpenAfterNominations');
        } else {
          data['poll_open_time'] = this.get('pollOpenTime');
        }
      }

      const pollClose = this.get('pollClose');
      data['poll_close'] = pollClose;
      if (pollClose) {
        const pollCloseAfter = this.get('pollCloseAfter');
        data['poll_close_after'] = pollCloseAfter;
        if (pollCloseAfter) {
          data['poll_close_after_hours'] = this.get('pollCloseAfterHours');
        } else {
          data['poll_close_time'] = this.get('pollCloseTime');
        }
      }

      if (this.get('sameMessage')) {
        data['poll_message'] = data['nomination_message'];
        data['closed_poll_message'] = data['nomination_message'];
      }

      this.set('loading', true);
      ajax(`/election/create`, {type: 'POST', data}).then((result) => {
        this.set('loading', false);

        if (result.url) {
          DiscourseURL.routeTo(result.url);
        }
      });
    }
  }
});
