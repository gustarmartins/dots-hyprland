#!/usr/bin/env python3
"""Synthetic fixtures only: never read the operator's mailbox or credentials."""
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bridge', ROOT / 'dots/.local/lib/qs-mail/bridge.py')
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class Startup(unittest.TestCase):
    def run_service(self):
        with patch.object(bridge.sys, 'argv', ['qs-mail', 'run']), \
             patch.object(bridge.sys, 'stderr', new_callable=io.StringIO) as stderr:
            with self.assertRaises(SystemExit) as result:
                bridge.main()
            return result.exception.code, stderr.getvalue()

    def test_missing_thunderbird_stops_without_restart(self):
        with patch.object(bridge, 'settings', return_value={'enabled': True}), \
             patch.object(bridge.shutil, 'which', return_value=None):
            code, message = self.run_service()
        self.assertEqual(code, 75)
        self.assertIn('Thunderbird is not installed', message)

    def test_missing_profile_stops_without_restart(self):
        with patch.object(bridge, 'settings', return_value={'enabled': True}), \
             patch.object(bridge.shutil, 'which', return_value='/usr/bin/thunderbird'), \
             patch.object(bridge, 'profile', side_effect=RuntimeError('no profile')):
            code, message = self.run_service()
        self.assertEqual(code, 75)
        self.assertIn('create a mail profile', message)

    def test_executable_disappears_before_exec(self):
        with patch.object(bridge, 'settings', return_value={'enabled': True}), \
             patch.object(bridge.shutil, 'which', return_value='/usr/bin/thunderbird'), \
             patch.object(bridge, 'profile', return_value=Path('/tmp/profile')), \
             patch.object(bridge, 'profile_running', return_value=False), \
             patch.object(bridge.os, 'execvp', side_effect=FileNotFoundError):
            code, message = self.run_service()
        self.assertEqual(code, 75)
        self.assertIn('Thunderbird is not installed', message)


class Extraction(unittest.TestCase):
    def test_rating_program_identity_actions_without_application_in_subject(self):
        sender = 'Program <notifications@example.invalid>'
        for subject in [
            'Quality Assurance Rating Program - Document Verification Step',
            'Rater project: Identity verification required',
        ]:
            self.assertTrue(bridge.career_update(sender, subject), subject)
        for subject in [
            'Bank account document verification step',
            'Your identity verification is complete',
            'Newsletter: Rating program document verification guide',
            'Rating program news and events',
        ]:
            self.assertFalse(bridge.career_update(sender, subject), subject)

    def test_application_questionnaires_from_generic_platform_sender(self):
        sender = 'Application platform <notifications@example.invalid>'
        for subject in [
            'Candidatura à vaga de Android Developer Pleno - Example Motors',
            'Candidatura para a vaga de QA não finalizada',
        ]:
            self.assertTrue(bridge.career_update(sender, subject, 'Preencha o formulário para continuarmos.'), subject)
        for subject, body in [
            ('Como enviar candidatura à vaga de QA', ''),
            ('Newsletter de carreira', 'Dicas para escrever: candidatura à vaga de QA.'),
            ('Vagas da semana', 'Candidatura para a vaga de QA.'),
        ]:
            self.assertFalse(bridge.career_update(sender, subject, body), subject)

    def test_portuguese_application_receipts_with_generic_senders(self):
        for subject in [
            'Inscrição recebida para a vaga Estágio em Testes de Software',
            'Inscrição recebida para a vaga ANALISTA SUPORTE JR N1',
            'Obrigado por se candidatar a vaga de Front-end Android Developer Pleno',
            'Obrigada por candidatar-se à vaga de QA',
        ]:
            self.assertTrue(bridge.career_update('Platform <no-reply@example.invalid>', subject), subject)
        for subject in [
            'Inscrição recebida para o webinar de tecnologia',
            'Saia na frente: 10 novas vagas de Programador para se candidatar',
            'ALS está contratando: Auxiliar Técnico Jr.',
        ]:
            self.assertFalse(bridge.career_update('News <news@example.invalid>', subject), subject)

    def test_career_updates_and_quiet_routine_mail(self):
        for subject, body in [
            ('Recebemos sua candidatura — Android', ''),
            ('Next Steps for Your Job Application: QA', ''),
            ('Security code for your application to Example', ''),
            ('Interview invitation', ''),
            ('Atualização do processo seletivo', ''),
            ('Your application status', 'We will not be moving forward'),
            ('Re: Android Developer', 'Can we talk on Monday?'),
            ('A quick update', 'Thank you for applying. We have selected another candidate.'),
        ]:
            self.assertTrue(bridge.career_update('Hiring <team@example.invalid>', subject, body), subject)
        for subject, body in [
            ('Seu perfil se encaixa perfeitamente com essas 10 vagas', 'Veja sua candidatura'),
            ('Melhores vagas da semana', 'Application links'),
            ('Jobs for you', 'Your application could stand out'),
            ('Your receipt', 'Your payment was received'),
            ('Gustavo, confirme seu novo dispositivo', 'Security verification'),
            ('Sale today', 'New products available'),
        ]:
            self.assertFalse(bridge.career_update('News <news@example.invalid>', subject, body), subject)

    def scan(self, subject, body, typ='text/plain'):
        return bridge.extract(subject, [{'type':typ, 'text':body}])

    def test_code_beyond_notification_preview(self):
        _, code, _ = self.scan('Sign in', 'Text\n' * 500 + 'Your verification code is 123456')
        self.assertEqual(code, '123456')

    def test_html_code_and_real_link(self):
        body, code, links = self.scan('Sign in', '<style>123456</style><p>Your verification code</p><b>345 678</b><a href="https://login.example/verify?a=1&amp;b=2">Continue</a><img src="https://tracker.example/pixel">', 'text/html')
        self.assertEqual(code, '345678')
        self.assertEqual(links, [{'url':'https://login.example/verify?a=1&b=2', 'label':'login.example'}])
        self.assertNotIn('123456', body)

    def test_portuguese(self):
        self.assertEqual(self.scan('Acesso', 'Seu código de verificação: 789123')[1], '789123')

    def test_order_and_invoice_are_not_otp(self):
        for text in ['Order number 123456', 'Invoice 654321', 'Your verification invoice 123456', 'Security update 2026']:
            self.assertEqual(self.scan('Receipt', text)[1], '')

    def test_ambiguous_codes_are_not_guessed(self):
        self.assertEqual(self.scan('Verify', 'Your login code is 123456\nYour security code is 987654')[1], '')

    def test_inert_html_and_schemes(self):
        body, _, links = self.scan('Hello', '<script>bad()</script><a href="javascript:alert(1)">x</a><a href="file:///etc/passwd">y</a><a href="https://a.example/unsubscribe">bye</a><a href="https://a.example/verify">yes</a>', 'text/html')
        self.assertNotIn('bad()', body)
        self.assertEqual(len(links), 1)
        for url in ['file:///tmp/test', 'javascript:alert(1)', 'https://x:y@example.com', 'https://x.example:bad', 'https://x.example/\nhello']:
            self.assertEqual(bridge.safe_url(url), '')

    def test_alternate_html_code_not_lost(self):
        _, code, _ = bridge.extract('Account', [{'type':'text/plain','text':'Open the HTML version'}, {'type':'text/html','text':'<p>Security code: 654987</p>'}])
        self.assertEqual(code, '654987')

    def test_bounded_links_deduplicated(self):
        _, _, links = self.scan('Hello', ' '.join(['https://example.com/verify'] * 20 + [f'https://example.org/{i}' for i in range(10)]))
        self.assertEqual(len(links), 3)
        self.assertEqual(links[0]['url'], 'https://example.com/verify')

    def test_window_show_hide_and_toggle(self):
        dispatched = []
        state = {'ws': 'special:mail'}
        orig_json, orig_dispatch = bridge.hypr_json, bridge.hypr_dispatch
        try:
            bridge.hypr_json = lambda *a: (
                [{'address': '0xabc', 'class': 'org.mozilla.Thunderbird', 'floating': False, 'workspace': {'name': state['ws']}}]
                if a == ('clients',) else {'id': 2, 'name': '2'}
            )
            bridge.hypr_dispatch = lambda expr: (dispatched.append(expr) or True)
            self.assertTrue(bridge.show_window())
            self.assertEqual(len(dispatched), 2)
            self.assertIn('workspace = "2"', dispatched[0])
            self.assertIn('hl.dsp.focus', dispatched[1])

            dispatched.clear()
            state['ws'] = '2'
            self.assertTrue(bridge.hide_window())
            self.assertEqual(len(dispatched), 1)
            self.assertIn('workspace = "special:mail"', dispatched[0])

            dispatched.clear()
            bridge.toggle_window()
            self.assertEqual(len(dispatched), 1)
            self.assertIn('workspace = "special:mail"', dispatched[0])
        finally:
            bridge.hypr_json, bridge.hypr_dispatch = orig_json, orig_dispatch


if __name__ == '__main__': unittest.main()
